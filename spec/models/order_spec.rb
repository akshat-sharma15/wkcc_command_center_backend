require "rails_helper"

RSpec.describe Order, type: :model do
  it "is valid with an order_number" do
    expect(build(:order)).to be_valid
  end

  it "requires a unique order_number" do
    create(:order, order_number: "ORD-DUP")
    expect(build(:order, order_number: "ORD-DUP")).not_to be_valid
  end

  it "allows nil origin_hub and destination_hub" do
    expect(build(:order, origin_hub: nil, destination_hub: nil)).to be_valid
  end

  it "rejects a negative package_count" do
    expect(build(:order, package_count: -1)).not_to be_valid
  end

  it "rejects a negative total_weight" do
    expect(build(:order, total_weight: -1)).not_to be_valid
  end

  it "allows a nil total_weight" do
    expect(build(:order, total_weight: nil)).to be_valid
  end

  describe "status enum" do
    it "exposes pending/processing/in_transit/delivered/cancelled" do
      expect(described_class.statuses.keys).to contain_exactly(
        "pending", "processing", "in_transit", "delivered", "cancelled"
      )
    end
  end

  it "has many packages, nullified when the order is destroyed" do
    order = create(:order)
    package = create(:package, order: order)

    order.destroy!

    expect(package.reload.order_id).to be_nil
  end
end
