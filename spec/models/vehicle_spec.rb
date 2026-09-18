require "rails_helper"

RSpec.describe Vehicle, type: :model do
  it "is valid with a hub, number, and vehicle_type" do
    expect(build(:vehicle)).to be_valid
  end

  it "requires a unique number" do
    create(:vehicle, number: "VH-DUP")
    expect(build(:vehicle, number: "VH-DUP")).not_to be_valid
  end

  it "requires a hub" do
    expect(build(:vehicle, hub: nil)).not_to be_valid
  end

  it "allows a nil driver" do
    expect(build(:vehicle, driver: nil)).to be_valid
  end

  it "associates a driver from workforce_members when present" do
    hub = create(:hub)
    driver = create(:workforce_member, hub: hub, role_type: "driver")
    vehicle = create(:vehicle, hub: hub, driver: driver)

    expect(vehicle.driver).to eq(driver)
  end

  describe "status enum" do
    it "exposes active/maintenance/out_of_service" do
      expect(described_class.statuses.keys).to contain_exactly("active", "maintenance", "out_of_service")
    end
  end
end
