# The ONE incident representation shared by every channel: Slack blocks
# (SlackIncidentMessageBuilder), the in-app notification list/detail
# (NotificationSerializer) and the realtime SSE payloads
# (RealtimeNotificationPublisher) all render this hash, so they always
# carry the same facts, the same labelled rows and the same actions.
#
# Built live from the Alert: `status` and assignment always reflect the
# current Alert record, while the operational facts come from the
# incident snapshot AlertEnrichmentService stored when the alert fired.
# Deliberately compact - no waybill/package collections (those are one
# click away via links[:waybills]).
class IncidentNotificationPresenter
  ACTIONS = %w[view_incident view_truck view_route view_hub view_waybills acknowledge assign reassign escalate resolve].freeze

  def initialize(alert)
    @alert = alert
    @incident = alert.metadata&.dig("incident") || {}
  end

  def advanced?
    @incident.present?
  end

  def as_json(*)
    return nil unless advanced?

    {
      alert_id: @alert.id,
      incident_type: @incident["key"],
      incident_title: @incident["title"],
      title: @alert.alert_rule&.name,
      severity: @alert.severity,
      status: @alert.status,
      triggered_at: @alert.triggered_at&.iso8601,
      summary: @incident["summary"],
      entity: { type: @alert.metadata&.dig("entity_type"), id: @alert.record_id },
      vehicle: @incident.dig("vehicle", "number"),
      driver: driver_label,
      route: route_label,
      diversion_route: @incident["diverted_route_label"],
      current_hub: @incident.dig("current_hub", "name"),
      destination: @incident.dig("next_hub", "name"),
      hub: @incident.dig("hub", "name"),
      planned_eta: @incident["planned_eta"],
      predicted_eta: @incident["predicted_eta"],
      delay_minutes: @incident["delay_minutes"],
      additional_distance_km: @incident["additional_distance_km"],
      waybill_count: @incident["waybill_count"],
      order_count: @incident["order_count"],
      package_count: @incident["package_count"],
      revenue_risk: @incident["revenue_risk"],
      sla_risk: @incident["sla_risk"],
      assignment: assignment,
      fields: fields,
      links: links,
      actions: actions,
      deep_link: deep_link
    }
  end

  # Labelled display rows, in display order - the exact rows Slack shows
  # and the in-app card/detail renders. Missing values are omitted.
  def fields
    [
      [ "Truck", @incident.dig("vehicle", "number") ],
      [ "Driver", driver_label ],
      [ "Hub", @incident.dig("hub", "name") ],
      [ "Route", route_label ],
      [ "Diversion", @incident["diverted_route_label"] ],
      [ "Current hub", @incident.dig("current_hub", "name") ],
      [ "Destination", @incident.dig("next_hub", "name") ],
      [ "Extra distance", @incident["additional_distance_km"] && "+#{@incident['additional_distance_km']} km" ],
      [ "ETA", eta_label ],
      [ "ETA delay", @incident["delay_minutes"] && "+#{@incident['delay_minutes']} min" ],
      [ "Waybills", @incident["waybill_count"] ],
      [ "Orders", @incident["order_count"] ],
      [ "Packages", @incident["package_count"] ],
      [ "Revenue risk", self.class.inr(@incident["revenue_risk"]) ],
      [ "Inbound / outbound", hub_counts ],
      [ "Projected load", projected_load ],
      [ "Requested vehicles", @incident["requested_vehicle_count"] ],
      [ "Reason", @incident["reason"] ],
      [ "Primary", assignment.dig(:primary, :name) ],
      [ "Secondary", assignment.dig(:secondary, :name) ],
      [ "Current", assignment.dig(:current, :name) ],
      [ "Status", @alert.status.to_s.upcase.tr("_", " ") ]
    ].filter_map { |label, value| { label: label, value: value.to_s } unless value.nil? || value == "" }
  end

  # Built from the snapshot's ids (not stored URLs) so every alert, old or
  # new, links into the same drill-through: the map opens with the truck,
  # route/diversion or hub selected and this incident's context shown.
  def links
    @links ||= begin
      id = @alert.id
      number = @incident.dig("vehicle", "number")
      hub_code = @incident.dig("hub", "code")
      destination_code = @incident.dig("next_hub", "code")
      {
        incident: IncidentLinks.incident(id),
        vehicle: IncidentLinks.vehicle(number, incident: id),
        route: IncidentLinks.route(number, diversion_id: @incident["diversion_id"], incident: id),
        hub: hub_code ? IncidentLinks.hub(hub_code, direction: "all", incident: id) : IncidentLinks.hub(destination_code, direction: "inbound", incident: id),
        waybills: @incident["trip_id"] && IncidentLinks.incident(id, section: "waybills")
      }.compact
    end
  end

  # Actions valid for the alert's current status (view actions whenever
  # their target exists).
  def actions
    available = %w[view_incident]
    available << "view_truck" if links[:vehicle]
    available << "view_route" if links[:route]
    available << "view_hub" if links[:hub]
    available << "view_waybills" if links[:waybills]
    return available if @alert.status_resolved?

    available << "acknowledge" if @alert.status_open? || @alert.status_escalated?
    available << (@alert.assignee ? "reassign" : "assign")
    secondary = @alert.alert_rule&.assignee_for(:secondary)
    available << "escalate" if secondary && @alert.assignment_level != "secondary"
    available << "resolve"
  end

  def assignment
    @assignment ||= begin
      rule = @alert.alert_rule
      {
        primary: principal(rule&.assignee_for(:primary)),
        secondary: principal(rule&.assignee_for(:secondary)),
        current: principal(@alert.assignee),
        level: @alert.assignment_level
      }
    end
  end

  def deep_link
    case @incident["key"]
    when IncidentCatalog::ROUTE_DIVERSION then { type: "route_diversion", id: @incident["diversion_id"] }
    when IncidentCatalog::HUB_EXTRA_VEHICLE_REQUEST then { type: "hub", id: @incident.dig("hub", "code") }
    when IncidentCatalog::VEHICLE_FAILURE then { type: "vehicle", id: @incident.dig("vehicle", "number") }
    end
  end

  # Indian digit grouping (₹2,35,000).
  def self.inr(amount)
    return nil if amount.nil?

    whole = amount.to_d.round.to_i.to_s
    head, tail = whole.length > 3 ? [ whole[0...-3], whole[-3..] ] : [ nil, whole ]
    grouped = head ? "#{head.reverse.scan(/\d{1,2}/).join(',').reverse},#{tail}" : tail
    "₹#{grouped}"
  end

  private

  def principal(ref)
    return nil unless ref

    name = SupersetDirectory.resolve_principal(ref[:type], ref[:id])&.fetch(:name, nil)
    { type: ref[:type], id: ref[:id], name: name || "#{ref[:type]} ##{ref[:id]}" }
  end

  def driver_label
    driver = @incident["driver"]
    driver && [ driver["name"], driver["phone"] ].compact.join(" · ")
  end

  def route_label
    @incident["original_route_label"].presence || @incident.dig("route", "label")
  end

  def eta_label
    eta = @incident["predicted_eta"] || @incident["planned_eta"]
    eta && Time.zone.parse(eta).in_time_zone("Asia/Kolkata").strftime("%d %b %H:%M IST")
  end

  def hub_counts
    inbound = @incident["inbound_vehicle_count"]
    outbound = @incident["outbound_vehicle_count"]
    "#{inbound} in / #{outbound} out" if inbound && outbound
  end

  def projected_load
    load = @incident["projected_load_kg"]
    return nil unless load

    capacity = @incident["capacity_kg"]
    text = "#{(load / 1000.0).round(1)} t"
    capacity ? "#{text} of #{(capacity / 1000.0).round(1)} t (#{@incident['projected_utilization_pct']}%)" : text
  end
end
