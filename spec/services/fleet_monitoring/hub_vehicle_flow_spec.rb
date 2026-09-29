require "rails_helper"

RSpec.describe FleetMonitoring::HubVehicleFlow do
  it "gives hub counts that equal the vehicles returned, from one query" do
    corridor = build_corridor
    other = create(:vehicle, fleet_monitoring_poc: true)
    create(:trip, vehicle: other, origin_hub: corridor[:destination], destination_hub: corridor[:origin], status: "in_transit")
    create(:trip, vehicle: create(:vehicle, fleet_monitoring_poc: false), origin_hub: corridor[:origin], destination_hub: corridor[:destination], status: "in_transit")
    create(:trip, vehicle: other, origin_hub: corridor[:origin], destination_hub: corridor[:destination], status: "completed")

    counts = described_class.counts_by_hub
    [ corridor[:origin], corridor[:destination] ].each do |hub|
      %w[inbound outbound].each do |direction|
        expect(counts.fetch(hub.id)[direction.to_sym]).to eq(described_class.rows(hub, direction).size)
      end
      presented = FleetMonitoring::HubPresenter.new(hub).as_json
      expect([ presented[:inbound], presented[:outbound] ]).to eq([ counts[hub.id][:inbound], counts[hub.id][:outbound] ])
    end
    expect(described_class.rows(corridor[:destination], "inbound").map { |r| r[:pnr] }).to eq([ "TRK-SPEC-1" ])
    expect(described_class.summary(corridor[:origin])).to include(inbound_count: 1, outbound_count: 1, total_count: 2)
  end

  it "counts each vehicle once, on its latest in-transit trip" do
    corridor = build_corridor
    create(:trip, vehicle: corridor[:vehicle], origin_hub: corridor[:destination], destination_hub: corridor[:origin],
                  status: "in_transit", departure_at: 10.hours.ago)
    expect(described_class.current_trips.where(vehicle_id: corridor[:vehicle].id).pluck(:id)).to eq([ corridor[:trip].id ])
  end
end
