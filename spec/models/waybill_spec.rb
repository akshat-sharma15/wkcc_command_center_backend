require "rails_helper"

RSpec.describe Waybill, type: :model do
  it "recalculates document totals from its packages and their orders" do
    corridor = build_corridor
    waybill = corridor[:waybill]

    expect(waybill.total_packages).to eq(2)
    expect(waybill.total_orders).to eq(1)
    expect(waybill.customer_count).to eq(1)
    # order weight 100 kg apportioned over its 2 packages -> 50 kg each
    expect(waybill.total_weight.to_f).to eq(100.0)
    expect(waybill.customer_reference).to eq("CUST-9")
  end

  it "requires a unique waybill number and distinct origin/destination" do
    existing = create(:waybill)
    duplicate = build(:waybill, waybill_number: existing.waybill_number)
    expect(duplicate).not_to be_valid

    hub = create(:hub)
    same_hub = build(:waybill, origin_hub: hub, destination_hub: hub)
    expect(same_hub).not_to be_valid
  end
end
