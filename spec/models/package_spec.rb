require "rails_helper"

RSpec.describe Package, type: :model do
  it "is valid with an identifier and a warehouse location" do
    expect(build(:package)).to be_valid
  end

  it "is valid with a hub as the location" do
    expect(build(:package, location: create(:hub))).to be_valid
  end

  it "requires a unique identifier" do
    create(:package, identifier: "PKG-DUP")
    expect(build(:package, identifier: "PKG-DUP")).not_to be_valid
  end

  it "rejects negative quantities" do
    expect(build(:package, damaged_quantity: -1)).not_to be_valid
  end

  describe "Command Centre shipment fields" do
    it "allows a nil order" do
      expect(build(:package, order: nil)).to be_valid
    end

    it "associates an order when present" do
      order = create(:order)
      package = create(:package, order: order)

      expect(package.order).to eq(order)
    end

    it "accepts promised_delivery_at and delivered_at" do
      promised = 2.days.from_now
      delivered = 1.day.from_now
      package = create(:package, promised_delivery_at: promised, delivered_at: delivered)

      expect(package.reload.promised_delivery_at).to be_within(1.second).of(promised)
      expect(package.reload.delivered_at).to be_within(1.second).of(delivered)
    end

    it "does not add the new fields to alertable_fields automatically" do
      package = create(:package)
      expect(package.alertable_fields).to eq([])
    end
  end

  describe "status transition history" do
    it "does not record a transition on create" do
      package = create(:package, status: "pending")
      expect(package.package_status_transitions).to be_empty
    end

    it "records a transition when status changes" do
      package = create(:package, status: "pending")

      package.update!(status: "in_transit")

      transitions = package.package_status_transitions.reload
      expect(transitions.size).to eq(1)
      expect(transitions.first.from_status).to eq("pending")
      expect(transitions.first.to_status).to eq("in_transit")
      expect(transitions.first.occurred_at).to be_present
    end

    it "does not record a transition for unrelated field updates" do
      package = create(:package, status: "pending")

      package.update!(received_quantity: 50)

      expect(package.package_status_transitions.reload).to be_empty
    end

    it "records a transition per status change, oldest first" do
      package = create(:package, status: "pending")

      package.update!(status: "in_transit")
      package.update!(status: "received")

      transitions = package.package_status_transitions.order(:occurred_at)
      expect(transitions.map(&:to_status)).to eq(%w[in_transit received])
    end

    it "removes transitions when the package is destroyed" do
      package = create(:package, status: "pending")
      package.update!(status: "in_transit")

      package.destroy!

      expect(PackageStatusTransition.where(package_id: package.id)).to be_empty
    end
  end
end
