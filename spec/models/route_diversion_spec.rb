require "rails_helper"

RSpec.describe RouteDiversion, type: :model do
  it "is valid with two waypoint paths" do
    expect(build(:route_diversion)).to be_valid
  end

  it "rejects paths without coordinates" do
    diversion = build(:route_diversion, diverted_path: [ { "name" => "Dhar" } ])
    expect(diversion).not_to be_valid
    expect(diversion.errors[:diverted_path]).to be_present
  end

  it "rejects a trip belonging to another vehicle" do
    diversion = build(:route_diversion, vehicle: create(:vehicle))
    expect(diversion).not_to be_valid
    expect(diversion.errors[:trip_id]).to be_present
  end
end
