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
end
