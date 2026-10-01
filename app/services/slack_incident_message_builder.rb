# Block Kit layout for an advanced-incident Slack message. Renders the
# shared IncidentNotificationPresenter (the same rows/actions the in-app
# incident UI shows) from the LIVE Alert, so re-rendering after an
# acknowledge/assign/escalate/resolve updates the posted message (see
# SlackIncidentSyncJob). Buttons are link buttons into the Command Center
# incident page, where the action runs against the same Alert record -
# Slack interactivity (a public request URL) is not configured.
# Returns nil for non-incident notifications, whose text is unchanged.
class SlackIncidentMessageBuilder
  SEVERITY_EMOJI = { "critical" => "🚨", "warning" => "⚠️", "info" => "ℹ️" }.freeze
  BUTTONS = {
    "view_incident" => [ "View Incident", nil ], "view_truck" => [ "View Truck", :vehicle ],
    "view_route" => [ "View Route", :route ], "view_hub" => [ "View Hub", :hub ],
    "acknowledge" => [ "Acknowledge", nil ], "assign" => [ "Assign", nil ],
    "reassign" => [ "Reassign", nil ], "resolve" => [ "Resolve", nil ]
  }.freeze

  def initialize(notification)
    @notification = notification
    @alert = notification.alert
    @presenter = @alert && IncidentNotificationPresenter.new(@alert)
  end

  def blocks
    return nil unless @presenter&.advanced?

    card = @presenter.as_json
    fields = card[:fields].reject { |row| row[:label] == "Status" }
    [
      { type: "header", text: { type: "plain_text", text: header(card), emoji: true } },
      { type: "section", text: { type: "mrkdwn", text: "*#{@notification.title}*\n#{card[:summary] || @notification.message}" } },
      *fields.each_slice(10).map { |slice| { type: "section", fields: slice.map { |row| { type: "mrkdwn", text: "*#{row[:label]}:*\n#{row[:value]}" } } } },
      { type: "context", elements: [ { type: "mrkdwn", text: status_line(card) } ] },
      { type: "actions", elements: buttons(card) }
    ]
  end

  private

  def header(card)
    "#{SEVERITY_EMOJI.fetch(card[:severity].to_s, '🔔')} #{card[:severity].to_s.upcase} — #{card[:incident_title].to_s.upcase}".truncate(150)
  end

  def status_line(card)
    current = card.dig(:assignment, :current, :name)
    "Status: *#{card[:status].to_s.upcase.tr('_', ' ')}*#{current ? " · Assigned: #{current}" : ''} · Alert ##{card[:alert_id]}"
  end

  def buttons(card)
    card[:actions].filter_map do |action|
      label, link_key = BUTTONS[action]
      next unless label

      url = link_key ? card.dig(:links, link_key) : IncidentLinks.incident(card[:alert_id], action: action == "view_incident" ? nil : action)
      next if url.blank?

      { type: "button", text: { type: "plain_text", text: label }, url: url, style: ("primary" if action == "view_incident") }.compact
    end.first(25)
  end
end
