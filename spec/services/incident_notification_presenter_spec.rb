require "rails_helper"

RSpec.describe IncidentNotificationPresenter do
  let(:rule) { create(:alert_rule, primary_assignee_type: "user", primary_assignee_id: 1, secondary_assignee_type: "role", secondary_assignee_id: 3) }
  let(:alert) do
    create(:alert, alert_rule: rule, metadata: { "entity_type" => "vehicles", "incident" => {
      "key" => "vehicle.failure", "title" => "Truck Failure", "summary" => "Truck TRK-9 has failed.",
      "vehicle" => { "number" => "TRK-9" }, "driver" => { "name" => "Ravi", "phone" => "+91 1" },
      "route" => { "label" => "Indore → Ratlam" }, "next_hub" => { "code" => "HUB-RTM", "name" => "Ratlam" },
      "current_hub" => { "name" => "Indore" }, "waybill_count" => 3, "order_count" => 4, "package_count" => 5,
      "delay_minutes" => 60, "revenue_risk" => 235_000, "trip_id" => 11, "planned_eta" => "2026-09-29T10:00:00Z", "predicted_eta" => "2026-09-29T11:00:00Z"
    } })
  end

  it "carries every core incident fact, assignment and deep link" do
    card = described_class.new(alert).as_json

    expect(card).to include(alert_id: alert.id, incident_type: "vehicle.failure", severity: "critical", status: "open",
                            vehicle: "TRK-9", route: "Indore → Ratlam", destination: "Ratlam", waybill_count: 3,
                            order_count: 4, package_count: 5, delay_minutes: 60, revenue_risk: 235_000,
                            deep_link: { type: "vehicle", id: "TRK-9" })
    expect(card[:assignment]).to include(primary: include(type: "user", id: 1), secondary: include(type: "role", id: 3),
                                         current: include(type: "user", id: 1), level: "primary")
    expect(card[:fields].map { |f| f[:label] }).to include("Truck", "Driver", "Route", "Current hub", "Destination", "ETA", "ETA delay",
                                                           "Waybills", "Orders", "Packages", "Revenue risk", "Primary", "Secondary", "Current", "Status")
    expect(card[:links].keys).to contain_exactly(:incident, :vehicle, :route, :hub, :waybills)
    expect(card[:actions]).to eq(%w[view_incident view_truck view_route view_hub view_waybills acknowledge reassign escalate resolve])
  end

  it "tracks the live alert status and current assignee" do
    alert.assign!(assignee_type: "user", assignee_id: 42, by: 1)
    card = described_class.new(alert.reload).as_json
    expect(card[:status]).to eq("in_progress")
    expect(card[:assignment][:current]).to include(id: 42)
    expect(card[:assignment][:primary]).to include(id: 1)
  end

  it "is nil for ordinary alerts" do
    expect(described_class.new(create(:alert)).as_json).to be_nil
  end
end
