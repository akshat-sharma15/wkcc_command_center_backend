require "rails_helper"

RSpec.describe Trip, type: :model do
  it "is valid with a vehicle, origin_hub, and destination_hub" do
    expect(build(:trip)).to be_valid
  end

  it "rejects the same hub as origin and destination" do
    hub = create(:hub)
    trip = build(:trip, origin_hub: hub, destination_hub: hub)
    expect(trip).not_to be_valid
  end
end
