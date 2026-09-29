require "rails_helper"

RSpec.describe RouteDiversionImpactService do
  it "calculates and persists distance, delay, ETA, fuel, waybill and revenue impact" do
    corridor = build_corridor(departure_at: 1.hour.ago, expected_arrival_at: 2.hours.from_now)
    diversion = create(:route_diversion, trip: corridor[:trip])

    result = described_class.new(diversion).apply!
    diversion.reload

    expect(diversion.original_distance_km.to_f).to be_within(1).of(130)
    expect(diversion.diverted_distance_km.to_f).to be_within(1).of(144)
    expect(diversion.additional_distance_km.to_f).to be > 0
    expect(diversion.delay_minutes).to be > 0
    expect(diversion.revised_eta).to eq(corridor[:trip].expected_arrival_at + diversion.delay_minutes.minutes)
    expect(diversion.fuel_impact_litres.to_f).to eq((diversion.additional_distance_km.to_f / 4.0).round(2))
    expect(diversion.affected_waybills).to eq(1)
    expect(diversion.affected_packages).to eq(2)
    expect(diversion.affected_orders).to eq(1)
    expect(diversion.revenue_risk.to_f).to eq(50_000.0)
    expect(result[:sla_risk]).to eq("high")
    expect(result[:distance_basis]).to eq("great_circle")
    expect(diversion.impact_snapshot["destination_hub_impact"]["hub"]["name"]).to eq("Ratlam Test Hub")
  end

  it "prefers operator-supplied road distances" do
    corridor = build_corridor
    diversion = create(:route_diversion, trip: corridor[:trip])
    described_class.new(diversion, original_distance_km: 140, diverted_distance_km: 185).apply!

    expect(diversion.reload.additional_distance_km.to_f).to eq(45.0)
    expect(diversion.impact_snapshot["distance_basis"]).to eq("operator_supplied")
  end

  it "leaves values nil and says why when inputs are missing" do
    corridor = build_corridor
    corridor[:vehicle].update!(fuel_efficiency_kmpl: nil)
    corridor[:waybill].update!(declared_value: nil)
    diversion = create(:route_diversion, trip: corridor[:trip])

    result = described_class.new(diversion).call
    expect(result[:fuel_impact_litres]).to be_nil
    expect(result[:revenue_risk]).to be_nil
    expect(result[:unavailable].join).to include("fuel_efficiency_kmpl", "no_declared_values")
  end
end
