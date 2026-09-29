require "rails_helper"

RSpec.describe SlackIncidentMessageBuilder do
  let(:rule) { create(:alert_rule, primary_assignee_type: "user", primary_assignee_id: 1, secondary_assignee_type: "role", secondary_assignee_id: 3) }
  let(:alert) do
    create(:alert, alert_rule: rule, severity: "critical", metadata: {
      "incident" => { "key" => "route.diversion", "title" => "Route Diversion", "vehicle" => { "number" => "TRK-102" },
                      "original_route_label" => "Indore → Ujjain → Ratlam", "diverted_route_label" => "Indore → Dhar → Ratlam",
                      "additional_distance_km" => 45, "delay_minutes" => 60, "waybill_count" => 12, "order_count" => 37,
                      "revenue_risk" => 235_000, "diversion_id" => 7, "trip_id" => 3, "next_hub" => { "code" => "HUB-RTM", "name" => "Ratlam" } }
    })
  end
  let(:notification) { create(:notification, alert: alert, channel: "slack") }

  it "renders the shared incident card rows, live status and action buttons" do
    blocks = described_class.new(notification).blocks
    text = blocks.to_json

    expect(blocks.first[:text][:text]).to eq("🚨 CRITICAL — ROUTE DIVERSION")
    expect(text).to include("+45 km", "+60 min", "₹2,35,000", "Indore → Dhar → Ratlam", "Status: *OPEN*")
    labels = blocks.last[:elements].map { |e| e[:text][:text] }
    expect(labels).to eq([ "View Incident", "View Truck", "View Route", "View Hub", "Acknowledge", "Reassign", "Resolve" ])
    expect(blocks.last[:elements].first[:url]).to end_with("/incident/#{alert.id}")
    expect(blocks.last[:elements].find { |e| e[:text][:text] == "View Route" }[:url]).to include("diversion=7", "incident=#{alert.id}")
  end

  it "shows the same rows as the in-app card" do
    card = IncidentNotificationPresenter.new(alert).as_json
    slack_rows = described_class.new(notification).blocks.select { |b| b[:fields] }.flat_map { |b| b[:fields].map { |f| f[:text] } }
    expect(slack_rows).to eq(card[:fields].reject { |f| f[:label] == "Status" }.map { |f| "*#{f[:label]}:*\n#{f[:value]}" })
  end

  it "reflects lifecycle changes on the same alert" do
    alert.acknowledge!(by: 1)
    expect(described_class.new(notification.reload).blocks.to_json).to include("Status: *ACKNOWLEDGED*")
    alert.resolve!(by: 1, note: "done")
    buttons = described_class.new(notification.reload).blocks.last[:elements].map { |e| e[:text][:text] }
    expect(buttons).not_to include("Acknowledge", "Resolve")
  end

  it "returns nil for ordinary alerts so their Slack text is unchanged" do
    expect(described_class.new(create(:notification, channel: "slack")).blocks).to be_nil
  end
end
