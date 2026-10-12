require "rails_helper"

RSpec.describe "scripts/data/refresh_trip_etas.rb" do
  let(:script) { Rails.root.join("scripts/data/refresh_trip_etas.rb") }

  def run_script(apply:)
    original = ENV["APPLY"]
    ENV["APPLY"] = apply ? "1" : nil
    expect { load script }.to output.to_stdout
  ensure
    ENV["APPLY"] = original
  end

  it "makes a stale diverted trip's card ETA equal its revised ETA, without moving the truck" do
    corridor = build_corridor(departure_at: 20.days.ago, expected_arrival_at: 20.days.ago + 4.hours)
    trip = corridor[:trip]
    diversion = create(:route_diversion, trip: trip, traffic_factor: 1.2)
    RouteDiversionImpactService.new(diversion).apply!
    vehicle = corridor[:vehicle].reload
    position = [ vehicle.current_location_id, vehicle.last_known_latitude, vehicle.last_known_longitude, vehicle.updated_at ]
    waybill_arrival = corridor[:waybill].reload.expected_arrival_at
    trip_arrival = trip.reload.expected_arrival_at

    run_script(apply: false)
    expect(trip.reload.expected_arrival_at).to be < 10.days.ago # dry run writes nothing

    run_script(apply: true)

    trip.reload
    diversion.reload
    eta = EtaImpactService.new(trip)
    expect(trip.expected_arrival_at).to be > Time.current
    expect(diversion.revised_eta).to be_within(3.minutes).of(eta.predicted_eta) # times are kept to whole minutes
    expect(eta.eta_variance_minutes).to be_within(3).of(diversion.delay_minutes) # card "late by" = diversion delay
    expect(corridor[:waybill].reload.expected_arrival_at - waybill_arrival).to be_within(1.second).of(trip.expected_arrival_at - trip_arrival) # shifted with its trip
    vehicle.reload
    expect([ vehicle.current_location_id, vehicle.last_known_latitude, vehicle.last_known_longitude, vehicle.updated_at ]).to eq(position)
  end

  it "puts a stale undiverted trip on time, and leaves an up-to-date trip alone on a re-run" do
    trip = build_corridor(departure_at: 20.days.ago, expected_arrival_at: 20.days.ago + 4.hours)[:trip]

    run_script(apply: true)
    eta = EtaImpactService.new(trip.reload)
    expect(eta.eta_variance_minutes.abs).to be <= 3

    expect { run_script(apply: true) }.not_to(change { trip.reload.updated_at })
  end
end
