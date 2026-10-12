require "rails_helper"

RSpec.describe "Api::V1::FleetMonitoring road routes", type: :request do
  let(:google) { "https://routes.googleapis.com/directions/v2:computeRoutes" }
  let(:route_body) { { routes: [ { polyline: { encodedPolyline: "_p~iF~ps|U_ulLnnqC" }, distanceMeters: 123_000 } ] }.to_json }

  around do |example|
    original = ENV["GOOGLE_ROUTES_API_KEY"]
    ENV["GOOGLE_ROUTES_API_KEY"] = "test-routes-key"
    example.run
    ENV["GOOGLE_ROUTES_API_KEY"] = original
  end

  def route_for(trip)
    get "/api/v1/fleet-monitoring/trips/#{trip.id}/road-route", headers: authenticated_headers
    response.parsed_body["route"]
  end

  it "fetches a route from Google once, then serves it from the database" do
    trip = build_corridor[:trip]
    stub_request(:post, google).to_return(status: 200, body: route_body)

    first = route_for(trip)
    second = route_for(trip)

    expect(first["encoded_polyline"]).to eq("_p~iF~ps|U_ulLnnqC")
    expect(second).to eq(first)
    expect(a_request(:post, google)).to have_been_made.once
    expect(RoadRoute.count).to eq(1)
    expect(RoadRoute.last).to have_attributes(distance_meters: 123_000)
    # The key is sent as a header only, with the field mask that keeps the response small.
    expect(a_request(:post, google).with(headers: { "X-Goog-Api-Key" => "test-routes-key", "X-Goog-FieldMask" => GoogleRoutesClient::FIELD_MASK })).to have_been_made
  end

  it "asks Google for origin hub -> truck position -> destination hub, as the map did" do
    corridor = build_corridor
    stub_request(:post, google).to_return(status: 200, body: route_body)

    route_for(corridor[:trip])

    expect(a_request(:post, google).with { |req|
      body = JSON.parse(req.body)
      ll = ->(p) { p.dig("location", "latLng").values_at("latitude", "longitude") }
      ll.(body["origin"]) == [ 22.7196, 75.8577 ] && ll.(body["destination"]) == [ 23.3315, 75.0367 ] &&
        body["intermediates"].map { |p| [ *ll.(p), p["via"] ] } == [ [ 23.1765, 75.7885, true ] ] && body["travelMode"] == "DRIVE"
    }).to have_been_made.once
  end

  it "shares one stored route between trucks at the same spot, and serves them all in one batch" do
    corridor = build_corridor
    same_spot = create(:vehicle, fleet_monitoring_poc: true, current_location_id: corridor[:ujjain].id)
    other_trip = create(:trip, vehicle: same_spot, origin_hub: corridor[:origin], destination_hub: corridor[:destination], status: "in_transit")
    stub_request(:post, google).to_return(status: 200, body: route_body)

    route_for(corridor[:trip])
    route_for(other_trip)

    expect(a_request(:post, google)).to have_been_made.once
    get "/api/v1/fleet-monitoring/road-routes", headers: authenticated_headers
    body = response.parsed_body
    expect(body["routes"].size).to eq(1)
    expect(body["trips"].keys).to contain_exactly(corridor[:trip].id.to_s, other_trip.id.to_s)
    expect(body["trips"].values.uniq).to eq(body["routes"].keys)
  end

  it "never calls Google from the batch endpoint" do
    build_corridor
    get "/api/v1/fleet-monitoring/road-routes", headers: authenticated_headers
    expect(response.parsed_body).to eq("routes" => {}, "trips" => {})
    expect(a_request(:post, google)).not_to have_been_made
  end

  it "returns no route when Google fails, and does not retry it straight away" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    trip = build_corridor[:trip]
    stub_request(:post, google).to_return(status: 429, body: { error: { message: "Quota exceeded" } }.to_json)

    expect(route_for(trip)).to be_nil
    expect(route_for(trip)).to be_nil
    expect(a_request(:post, google)).to have_been_made.once
    expect(RoadRoute.count).to eq(0)
  end

  it "refreshes a stale route, and keeps serving it if the refresh fails" do
    trip = build_corridor[:trip]
    points = FleetMonitoring::RoadRouteService.waypoints_for(trip)
    RoadRoute.create!(route_key: RoadRoute.key_for(points), waypoints: points, encoded_polyline: "old", fetched_at: 40.days.ago)

    stub_request(:post, google).to_return(status: 503, body: "")
    expect(route_for(trip)["encoded_polyline"]).to eq("old")

    WebMock.reset!
    Rails.cache.clear
    stub_request(:post, google).to_return(status: 200, body: route_body)
    expect(route_for(trip)["encoded_polyline"]).to eq("_p~iF~ps|U_ulLnnqC")
  end

  it "serves stored routes but never calls Google without a key" do
    ENV["GOOGLE_ROUTES_API_KEY"] = nil
    trip = build_corridor[:trip]
    expect(route_for(trip)).to be_nil
    expect(a_request(:post, google)).not_to have_been_made
  end

  it "is 404 for a trip that is not an in-transit map trip" do
    trip = create(:trip, vehicle: create(:vehicle, fleet_monitoring_poc: false), origin_hub: create(:hub), destination_hub: create(:hub), status: "in_transit")
    get "/api/v1/fleet-monitoring/trips/#{trip.id}/road-route", headers: authenticated_headers
    expect(response).to have_http_status(:not_found)
  end
end
