require "rails_helper"

RSpec.describe RevenueRiskService do
  let(:trip) { create(:trip, status: "in_transit", expected_arrival_at: 2.hours.from_now) }

  it "sums declared value of waybills that arrive late" do
    late = create(:waybill, trip: trip, declared_value: 1000, expected_arrival_at: 1.hour.from_now)
    create(:waybill, trip: trip, declared_value: 5000, expected_arrival_at: 5.hours.from_now)

    service = described_class.new(trip.waybills.to_a, revised_arrival: 3.hours.from_now)
    expect(service.at_risk_waybills).to eq([ late ])
    expect(service.revenue_risk).to eq(1000)
  end

  it "treats every waybill as at risk when the revised arrival is unknown" do
    create_list(:waybill, 2, trip: trip, declared_value: 700)
    expect(described_class.new(trip.waybills.to_a, revised_arrival: nil).revenue_risk).to eq(1400)
  end

  it "returns nil rather than inventing a value when nothing is valued" do
    create(:waybill, trip: trip, declared_value: nil)
    json = described_class.new(trip.waybills.to_a, revised_arrival: nil).as_json
    expect(json[:revenue_risk]).to be_nil
    expect(json[:unavailable]).to eq("no_declared_values")
  end
end
