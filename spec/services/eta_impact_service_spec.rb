require "rails_helper"

RSpec.describe EtaImpactService do
  it "derives planned pace and predicts ETA from the vehicle's position" do
    corridor = build_corridor
    eta = described_class.new(corridor[:trip])

    expect(eta.planned_speed_kmph).to be > 0
    expect(eta.remaining_km).to be < GeoDistance.path_km(eta.planned_route)
    expect(eta.predicted_eta).to be > Time.current
    expect(eta.as_json).to include(diverted: false, current_hub: include(name: "Indore Test Hub"), next_hub: include(name: "Ratlam Test Hub"))
  end

  it "reports unavailable instead of guessing for a stopped vehicle" do
    corridor = build_corridor
    corridor[:vehicle].update!(status: "maintenance")
    eta = described_class.new(corridor[:trip].reload)

    expect(eta.predicted_eta).to be_nil
    expect(eta.unavailable_reason).to eq("vehicle_stopped")
  end

  it "follows the diverted path of an active diversion" do
    corridor = build_corridor
    diversion = create(:route_diversion, trip: corridor[:trip], traffic_factor: 1.5)
    eta = described_class.new(corridor[:trip])

    expect(eta.diversion).to eq(diversion)
    expect(eta.current_route.map { |p| p["name"] }).to include("Dhar")
    expect(eta.traffic_factor).to eq(1.5)
  end
end
