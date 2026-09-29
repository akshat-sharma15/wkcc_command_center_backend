require "rails_helper"

RSpec.describe "Api::V1::FleetMonitoring::SearchSuggestions", type: :request do
  let(:path) { "/api/v1/fleet-monitoring/search/suggestions" }
  let(:indore) { Location.create!(city: "Indore", state: "Madhya Pradesh", latitude: 22.7196, longitude: 75.8577) }
  def body = response.parsed_body
  def suggestions = body["suggestions"]

  def suggest(q, **extra)
    get path, params: { q: q, **extra }, headers: authenticated_headers
  end

  describe "minimum query length" do
    it "rejects a query shorter than 3 characters" do
      suggest("VH")
      expect(response).to have_http_status(:bad_request)
      expect(body["error"]).to eq("q must be at least 3 characters")
    end

    it "ignores surrounding whitespace when counting characters" do
      suggest("  ab  ")
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a missing query" do
      get path, headers: authenticated_headers
      expect(response).to have_http_status(:bad_request)
    end

    it "accepts exactly 3 characters" do
      suggest("xyz")
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PNR / tracking identifier matches" do
    it "returns matching POC vehicles by PNR, prefix matches first" do
      create(:vehicle, number: "TRK-ZZ-001", fleet_monitoring_poc: true)
      prefix = create(:vehicle, number: "AB-001", fleet_monitoring_poc: true, current_geo_location: indore, vendor: "Blue Dart")
      create(:vehicle, number: "AB-002", fleet_monitoring_poc: true, status: "maintenance")

      suggest("ab-00")

      expect(response).to have_http_status(:ok)
      expect(suggestions["vehicles"].map { |v| v["pnr"] }).to eq(%w[AB-001 AB-002])
      expect(suggestions["vehicles"].first).to eq(
        "kind" => "vehicle", "pnr" => prefix.number, "label" => "AB-001",
        "detail" => "Indore, Madhya Pradesh · Blue Dart", "status" => "PARKED"
      )
      expect(suggestions["vehicles"].second["status"]).to eq("MAINTENANCE")
    end

    it "ranks a prefix match ahead of a substring match" do
      create(:vehicle, number: "XX-ABC", fleet_monitoring_poc: true)
      create(:vehicle, number: "ABC-99", fleet_monitoring_poc: true)

      suggest("ABC")

      expect(suggestions["vehicles"].map { |v| v["pnr"] }).to eq(%w[ABC-99 XX-ABC])
    end

    it "reports IN TRANSIT for a vehicle with an in-transit trip" do
      vehicle = create(:vehicle, number: "MOV-001", fleet_monitoring_poc: true)
      create(:trip, vehicle: vehicle, status: "in_transit")

      suggest("MOV")

      expect(suggestions["vehicles"].first["status"]).to eq("IN TRANSIT")
    end

    it "excludes vehicles outside the Fleet Monitoring POC" do
      create(:vehicle, number: "NOPOC-1", fleet_monitoring_poc: false)

      suggest("NOPOC")

      expect(suggestions["vehicles"]).to eq([])
    end
  end

  describe "hub matches" do
    it "matches hubs by code or name" do
      create(:hub, code: "IDR-01", name: "Indore Central", geo_location: indore, operational_status: "degraded")
      create(:hub, code: "JPR-01", name: "Jaipur Indore Road")
      create(:hub, code: "BOM-01", name: "Mumbai West")

      suggest("idr")
      expect(suggestions["hubs"]).to eq([
        { "kind" => "hub", "code" => "IDR-01", "label" => "Indore Central",
          "detail" => "IDR-01 · Indore, Madhya Pradesh", "status" => "HIGH LOAD" }
      ])

      suggest("indore")
      expect(suggestions["hubs"].map { |h| h["code"] }).to eq(%w[IDR-01 JPR-01])
    end
  end

  describe "package matches" do
    it "matches packages by package ID, describing where each one is" do
      vehicle = create(:vehicle, number: "VH-0042")
      trip = create(:trip, vehicle: vehicle, status: "in_transit")
      hub = create(:hub, name: "Indore Central")
      create(:package, identifier: "KWS4567", status: "in_transit", trip: trip)
      create(:package, identifier: "KWS4568", status: "received", location: hub)
      create(:package, identifier: "KWS4570", status: "delivered")
      create(:package, identifier: "OTHER-1")

      suggest("kws45")

      expect(suggestions["packages"]).to eq([
        { "kind" => "package", "id" => "KWS4567", "label" => "KWS4567", "detail" => "On VH-0042", "status" => "IN TRANSIT" },
        { "kind" => "package", "id" => "KWS4568", "label" => "KWS4568", "detail" => "Indore Central", "status" => "AT HUB" },
        { "kind" => "package", "id" => "KWS4570", "label" => "KWS4570", "detail" => nil, "status" => "DELIVERED" }
      ])
    end

    it "treats LIKE wildcards in the query literally" do
      create(:package, identifier: "PKG-ABC")

      suggest("%%%")

      expect(suggestions["packages"]).to eq([])
    end
  end

  describe "result limits" do
    before do
      12.times { |i| create(:package, identifier: format("LIM-%02d", i)) }
      12.times { |i| create(:vehicle, number: format("LIM-V%02d", i), fleet_monitoring_poc: true) }
    end

    it "returns at most 5 suggestions per category by default" do
      suggest("LIM")

      expect(body["limit"]).to eq(5)
      expect(suggestions["packages"].size).to eq(5)
      expect(suggestions["vehicles"].size).to eq(5)
      expect(suggestions["packages"].map { |p| p["id"] }).to eq(%w[LIM-00 LIM-01 LIM-02 LIM-03 LIM-04])
    end

    it "honours a smaller requested limit" do
      suggest("LIM", limit: 2)

      expect(suggestions["packages"].size).to eq(2)
      expect(suggestions["vehicles"].size).to eq(2)
    end

    it "caps the requested limit at 10" do
      suggest("LIM", limit: 500)

      expect(body["limit"]).to eq(10)
      expect(suggestions["packages"].size).to eq(10)
    end
  end

  describe "no results" do
    it "returns empty categories when nothing matches" do
      create(:vehicle, number: "VH-0001", fleet_monitoring_poc: true)
      create(:hub, code: "IDR-01")
      create(:package, identifier: "KWS4567")

      suggest("nomatch")

      expect(response).to have_http_status(:ok)
      expect(body).to eq(
        "query" => "nomatch", "limit" => 5,
        "suggestions" => { "vehicles" => [], "hubs" => [], "packages" => [], "waybills" => [] }
      )
    end
  end
end
