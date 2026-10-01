require "rails_helper"

RSpec.describe AlertEnrichmentService do
  it "enriches a truck failure alert through the normal EventPublisher pipeline" do
    corridor = build_corridor
    incident_rule(IncidentCatalog::VEHICLE_FAILURE, primary_assignee_type: "user", primary_assignee_id: 5)

    alerts = IncidentPublisher.publish(IncidentCatalog::VEHICLE_FAILURE, entity_id: corridor[:vehicle].id,
                                                                         payload: { "estimated_repair_minutes" => 90 })
    incident = alerts.first.reload.metadata["incident"]

    expect(incident).to include("key" => "vehicle.failure", "title" => "Truck Failure", "waybill_count" => 1,
                                "package_count" => 2, "order_count" => 1, "revenue_risk" => 50_000.0)
    expect(incident.dig("vehicle", "number")).to eq("TRK-SPEC-1")
    expect(incident.dig("driver", "name")).to eq("Test Driver")
    expect(incident.dig("next_hub", "name")).to eq("Ratlam Test Hub")
    expect(incident["delay_minutes"]).to be >= 90
    expect(incident.dig("links", "vehicle")).to include("vehicle=TRK-SPEC-1")
    expect(alerts.first.assignee).to eq(type: "user", id: 5)
    expect(VehicleOperationEvent.where(vehicle: corridor[:vehicle], event_type: "BREAKDOWN")).to exist
  end

  it "enriches an extra vehicle request with hub load" do
    corridor = build_corridor(expected_arrival_at: 1.hour.from_now)
    incident_rule(IncidentCatalog::HUB_EXTRA_VEHICLE_REQUEST)

    alert = IncidentPublisher.publish(IncidentCatalog::HUB_EXTRA_VEHICLE_REQUEST, entity_id: corridor[:destination].id,
                                                                                  payload: { "requested_vehicle_count" => 2, "reason" => "Demand" }).first
    incident = alert.reload.metadata["incident"]

    expect(incident).to include("requested_vehicle_count" => 2, "reason" => "Demand", "inbound_vehicle_count" => 1)
    expect(incident["projected_utilization_pct"]).to eq(20.0)
    expect(incident.dig("links", "hub")).to include("hub=#{corridor[:destination].code}")
  end

  it "leaves ordinary event alerts untouched" do
    rule = create(:alert_rule, trigger_type: "event", group: nil, field: nil, operator: nil, value: nil,
                               event_definition: create(:event_definition))
    alert = EventPublisher.publish(event_definition: rule.event_definition, entity_type: "vehicles", entity_id: 1).first
    expect(alert.reload.metadata).not_to have_key("incident")
  end

  it "records an enrichment error without blocking the alert" do
    incident_rule(IncidentCatalog::VEHICLE_FAILURE)
    alert = IncidentPublisher.publish(IncidentCatalog::VEHICLE_FAILURE, entity_id: 0).first

    expect(alert).to be_persisted
    expect(alert.reload.metadata.dig("incident", "enrichment_error")).to be_present
  end
end
