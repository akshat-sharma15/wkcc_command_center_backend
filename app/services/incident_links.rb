# Deep links for incidents, built from configured base URLs (never
# hard-coded hosts): the Superset Command Center (FRONTEND_BASE_URL, the
# same variable SlackIntegrationsController redirects to) and the
# truck_monitoring fleet map (FLEET_MAP_BASE_URL). Paths/params match the
# real routes: Superset's `/notification/:id` page, and the map's
# `?vehicle=` / `?hub=&direction=` / `?diversion=` deep-link parameters
# (see truck_monitoring app.js#applyDeepLink).
module IncidentLinks
  module_function

  def frontend_base
    ENV.fetch("FRONTEND_BASE_URL", "http://localhost:9000").chomp("/")
  end

  def map_base
    ENV.fetch("FLEET_MAP_BASE_URL", "http://localhost:4173").chomp("/")
  end

  # The Command Center incident page for one Alert (all users, all
  # channels). `section`/`action` pre-open a section or action there.
  def incident(alert_id, section: nil, action: nil)
    return nil unless alert_id

    query = { section: section, action: action }.compact
    "#{frontend_base}/incident/#{alert_id}#{query.any? ? "?#{query.to_query}" : ''}"
  end

  def notification(notification_id)
    notification_id && "#{frontend_base}/notification/#{notification_id}"
  end

  # `incident:` (an Alert id) lets the map show that incident's context.
  def vehicle(number, incident: nil)
    number && map_url({ vehicle: number, incident: incident }.compact)
  end

  def route(number, diversion_id: nil, incident: nil)
    return nil unless number

    params = diversion_id ? { vehicle: number, diversion: diversion_id } : { vehicle: number, route: 1 }
    map_url(params.merge(incident: incident).compact)
  end

  def hub(code, direction: nil, incident: nil)
    code && map_url({ hub: code, direction: direction, incident: incident }.compact)
  end

  def map_url(params)
    "#{map_base}/?#{params.to_query}"
  end
end
