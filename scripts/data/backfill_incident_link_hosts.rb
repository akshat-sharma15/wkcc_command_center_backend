# Rewrites the HOST of incident deep links already stored in the
# database, after FRONTEND_BASE_URL / FLEET_MAP_BASE_URL change.
#
#   bin/rails runner scripts/data/backfill_incident_link_hosts.rb
#   DRY_RUN=1 bin/rails runner scripts/data/backfill_incident_link_hosts.rb
#   OLD_HOSTS=http://localhost:9000,http://localhost:4173 bin/rails runner ...
#
# WHY: IncidentLinks builds URLs from those two env vars, but the result
# is SNAPSHOTTED into JSON at the moment an alert is enriched and a
# notification is delivered:
#   alerts.metadata        -> incident.links.{vehicle,route,hub}
#   notifications.metadata -> incident.links.{incident,vehicle,route,hub,waybills}
# Changing the env only affects records created afterwards; everything
# already stored keeps pointing at the old host. Slack messages
# themselves self-heal (SlackIncidentMessageBuilder re-renders from the
# LIVE presenter on the next lifecycle action), and so does anything else
# that goes through IncidentNotificationPresenter - but the raw stored
# blobs do not, and AlertSerializer/NotificationSerializer expose them.
#
# Only the scheme+host+port is replaced; the path and query (incident id,
# vehicle number, hub code, direction) are left exactly as they are.
#
# Idempotent: a record whose links already use the current base is
# skipped, so a second run reports zero changes.
DRY_RUN = ENV["DRY_RUN"].present?

NEW_FRONTEND = IncidentLinks.frontend_base
NEW_MAP = IncidentLinks.map_base

# Defaults cover the two historical values this project shipped with.
OLD_HOSTS = ENV.fetch("OLD_HOSTS", "http://localhost:9000,http://localhost:4173")
              .split(",").map { |h| h.strip.chomp("/") }.reject(&:empty?).freeze

# Which new base a given link belongs to is decided by the link's own
# shape, not by which old host it happened to use - a map link is any URL
# whose path is just "/" with a query (IncidentLinks#map_url), everything
# else is a Command Center page.
def rebase(url)
  return url unless url.is_a?(String)

  old = OLD_HOSTS.find { |h| url.start_with?("#{h}/") || url == h }
  return url unless old

  remainder = url[old.length..]
  base = remainder.start_with?("/?") ? NEW_MAP : NEW_FRONTEND
  "#{base}#{remainder}"
end

def rewrite_links(metadata)
  links = metadata&.dig("incident", "links")
  return [ metadata, false ] unless links.is_a?(Hash)

  updated = links.transform_values { |url| rebase(url) }
  return [ metadata, false ] if updated == links

  [ metadata.merge("incident" => metadata["incident"].merge("links" => updated)), true ]
end

puts "=" * 70
puts "BACKFILL INCIDENT LINK HOSTS#{DRY_RUN ? ' (DRY RUN - nothing will be written)' : ''}"
puts "=" * 70
puts "  old hosts : #{OLD_HOSTS.join(', ')}"
puts "  frontend  : #{NEW_FRONTEND}"
puts "  map       : #{NEW_MAP}"

if [ NEW_FRONTEND, NEW_MAP ].any? { |base| OLD_HOSTS.include?(base) }
  puts "\n  ⚠ a target base is also listed as an old host - set FRONTEND_BASE_URL/"
  puts "    FLEET_MAP_BASE_URL first, or pass OLD_HOSTS explicitly. Nothing done."
  exit
end

{ "alerts" => Alert, "notifications" => Notification }.each do |label, model|
  changed = 0
  examples = []

  model.where.not(metadata: nil).find_each do |record|
    metadata, dirty = rewrite_links(record.metadata)
    next unless dirty

    examples << [ record.id, record.metadata.dig("incident", "links").values.first, metadata.dig("incident", "links").values.first ] if examples.size < 3
    record.update_columns(metadata: metadata) unless DRY_RUN # rubocop:disable Rails/SkipsModelValidations
    changed += 1
  end

  puts "\n  #{label}: #{DRY_RUN ? 'would update' : 'updated'} #{changed}"
  examples.each { |id, before, after| puts "    ##{id}  #{before}\n          -> #{after}" }
end

remaining = [ Alert, Notification ].sum do |model|
  model.where.not(metadata: nil).count do |record|
    Array(record.metadata.dig("incident", "links")&.values).any? { |u| OLD_HOSTS.any? { |h| u.to_s.start_with?(h) } }
  end
end
puts "\n  records still on an old host: #{remaining}#{remaining.zero? ? ' ✓' : ''}"
puts "\nNote: already-posted Slack messages keep their old buttons until the"
puts "next lifecycle action on that incident re-renders them (SlackIncidentSyncJob)."
