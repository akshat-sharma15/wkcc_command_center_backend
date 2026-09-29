require "rails_helper"

RSpec.describe "Incident parity, drill-through and live updates", type: :request do
  let(:user_headers) { authenticated_headers.merge("X-Superset-User-Id" => "1") }

  it "gives in-app notifications the same incident card Slack renders, and broadcasts actions" do
    corridor = build_corridor
    incident_rule(IncidentCatalog::VEHICLE_FAILURE, notify: true, recipient_type: "user", recipient_id: 1,
                                                   notification_channels: %w[in_app slack],
                                                   primary_assignee_type: "user", primary_assignee_id: 1)
    allow(AlertRecipientResolver).to receive(:new).and_return(instance_double(AlertRecipientResolver, user_ids: [ 1 ]))
    allow(NotificationDeliveryJob).to receive(:perform_async)
    alert = IncidentPublisher.publish(IncidentCatalog::VEHICLE_FAILURE, entity_id: corridor[:vehicle].id).first

    get "/api/v1/notifications", headers: user_headers
    in_app = response.parsed_body.find { |n| n["channel"] == "in_app" }
    slack = Notification.find_by(alert: alert, channel: "slack")
    card = in_app["incident"]
    expect(card).to include("vehicle" => "TRK-SPEC-1", "waybill_count" => 1, "status" => "open")
    slack_rows = SlackIncidentMessageBuilder.new(slack).blocks.select { |b| b[:fields] }.flat_map { |b| b[:fields].map { |f| f[:text] } }
    expect(slack_rows).to eq(card["fields"].reject { |f| f["label"] == "Status" }.map { |f| "*#{f['label']}:*\n#{f['value']}" })

    publisher = class_double(RealtimeNotificationPublisher, publish_incident_update: true).as_stubbed_const(transfer_nested_constants: true)
    allow(SlackIncidentSyncJob).to receive(:perform_async)
    post "/api/v1/alerts/#{alert.id}/acknowledge", headers: user_headers
    expect(response.parsed_body["card"]["status"]).to eq("acknowledged")
    expect(publisher).to have_received(:publish_incident_update).with(alert)
    expect(SlackIncidentSyncJob).to have_received(:perform_async).with(alert.id)

    get "/api/v1/notifications/#{in_app['id']}", headers: user_headers
    expect(response.parsed_body["incident"]["status"]).to eq("acknowledged")

    get "/api/v1/notifications", params: { channel: "in_app" }, headers: user_headers
    expect(response.parsed_body.map { |n| n["channel"] }.uniq).to eq([ "in_app" ])
  end

  it "re-renders delivered Slack messages from the live alert" do
    alert = create(:alert, metadata: { "incident" => { "key" => "vehicle.failure", "title" => "Truck Failure" } })
    notification = create(:notification, alert: alert, channel: "slack", status: "delivered", external_reference: "123.45",
                                         metadata: { "slack_channel" => "C123" })
    create(:integration, provider: "slack", status: "connected", enabled: true, bot_token: "xoxb-1") unless Integration.exists?(provider: "slack")
    Integration.find_by(provider: "slack").update!(status: "connected", enabled: true, bot_token: "xoxb-1")
    allow(SlackOauthClient).to receive(:update_message).and_return({ "ok" => true })

    alert.acknowledge!(by: 1)
    SlackIncidentSyncJob.new.perform(alert.id)

    expect(SlackOauthClient).to have_received(:update_message)
      .with(hash_including(channel: "C123", ts: "123.45", blocks: array_including(hash_including(type: "context"))))
    expect(notification.reload.status).to eq("delivered")
  end
end
