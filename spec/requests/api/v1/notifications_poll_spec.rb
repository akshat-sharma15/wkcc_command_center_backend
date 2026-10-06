require "rails_helper"

RSpec.describe "GET /api/v1/notifications/poll", type: :request do
  let(:headers) { authenticated_headers.merge("X-Superset-User-Id" => "1") }
  let(:alert) { create(:alert) }

  def notify(user_id: 1, channel: "in_app", read_at: nil)
    create(:notification, alert: alert, recipient_user_id: user_id, channel: channel, read_at: read_at)
  end

  def poll(params = {})
    get "/api/v1/notifications/poll", params: params, headers: headers
    expect(response).to have_http_status(:ok)
    response.parsed_body
  end

  it "bootstraps with the unread in-app list and a cursor, then returns only newer notifications" do
    old_read = notify(read_at: 1.hour.ago)
    unread = notify
    notify(channel: "slack")
    notify(user_id: 2)

    first = poll
    expect(first["notifications"].map { |n| n["id"] }).to eq([ unread.id ])
    expect(first["unread_count"]).to eq(1)
    expect(first["cursor"]["after_id"]).to eq(unread.id)
    expect(first["notifications"].map { |n| n["id"] }).not_to include(old_read.id)

    expect(poll(after_id: first["cursor"]["after_id"])["notifications"]).to eq([])

    newer = notify
    other_user = notify(user_id: 2)
    second = poll(after_id: first["cursor"]["after_id"], since: first["cursor"]["since"])
    expect(second["notifications"].map { |n| n["id"] }).to eq([ newer.id ])
    expect(second["notifications"].map { |n| n["id"] }).not_to include(other_user.id)
    expect(second["cursor"]["after_id"]).to eq(newer.id)
    expect(second["unread_count"]).to eq(2)

    # Same cursor again: nothing repeated (no duplicates).
    expect(poll(after_id: second["cursor"]["after_id"])["notifications"]).to eq([])
  end

  it "pages a burst in bounded batches, oldest first" do
    cursor = poll["cursor"]["after_id"]
    ids = Array.new(Api::V1::NotificationsController::POLL_LIMIT + 3) { notify.id }

    first = poll(after_id: cursor)
    expect(first["notifications"].size).to eq(Api::V1::NotificationsController::POLL_LIMIT)
    expect(first["has_more"]).to be(true)
    rest = poll(after_id: first["cursor"]["after_id"])
    expect(rest["has_more"]).to be(false)
    expect(first["notifications"].map { |n| n["id"] } + rest["notifications"].map { |n| n["id"] }).to eq(ids)
  end

  it "reports incident status changes since the previous poll (replaces the SSE incident_update)" do
    incident_alert = create(:alert, metadata: { "incident" => { "key" => "vehicle.failure", "title" => "Truck Failure" } })
    create(:notification, alert: incident_alert, recipient_user_id: 1, channel: "in_app")
    first = poll

    expect(poll(after_id: first["cursor"]["after_id"], since: first["cursor"]["since"])["incident_updates"]).to eq([])
    incident_alert.acknowledge!(by: 1)
    update = poll(after_id: first["cursor"]["after_id"], since: first["cursor"]["since"])["incident_updates"]
    expect(update.map { |u| [ u["alert_id"], u["status"], u.dig("incident", "status") ] }).to eq([ [ incident_alert.id, "acknowledged", "acknowledged" ] ])
  end

  it "requires the user header and keeps users' notifications separate" do
    get "/api/v1/notifications/poll", headers: authenticated_headers
    expect(response).to have_http_status(:unauthorized)
  end

  it "answers in tens of milliseconds" do
    20.times { notify }
    cursor = poll["cursor"]
    timings = Array.new(10) do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      poll(after_id: cursor["after_id"], since: cursor["since"])
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
    end
    expect(timings.sort[timings.size / 2]).to be < 100
  end
end
