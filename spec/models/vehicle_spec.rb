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

  describe "Command Centre fleet fields" do
    it "leaves current_location untouched and still present" do
      vehicle = create(:vehicle, current_location: "Indore, MP")
      expect(vehicle.current_location).to eq("Indore, MP")
    end

    it "defaults the new coordinate/mileage/fuel-efficiency fields to nil" do
      vehicle = create(:vehicle)

      expect(vehicle.last_known_latitude).to be_nil
      expect(vehicle.last_known_longitude).to be_nil
      expect(vehicle.last_location_at).to be_nil
      expect(vehicle.mileage_km).to be_nil
      expect(vehicle.fuel_efficiency_kmpl).to be_nil
    end

    it "accepts and persists coordinates, last_location_at, mileage, and fuel efficiency" do
      vehicle = create(:vehicle,
        last_known_latitude: 22.719568,
        last_known_longitude: 75.857727,
        last_location_at: Time.zone.parse("2026-09-24 10:00:00"),
        mileage_km: 45231.75,
        fuel_efficiency_kmpl: 8.5)

      vehicle.reload
      expect(vehicle.last_known_latitude).to eq(BigDecimal("22.719568"))
      expect(vehicle.last_known_longitude).to eq(BigDecimal("75.857727"))
      expect(vehicle.last_location_at).to eq(Time.zone.parse("2026-09-24 10:00:00"))
      expect(vehicle.mileage_km).to eq(BigDecimal("45231.75"))
      expect(vehicle.fuel_efficiency_kmpl).to eq(BigDecimal("8.5"))
    end

    it "does not add the new fields to alertable_fields automatically" do
      vehicle = create(:vehicle)
      expect(vehicle.alertable_fields).to eq([])
    end
  end
end
