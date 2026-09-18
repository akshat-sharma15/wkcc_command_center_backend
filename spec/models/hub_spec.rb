require "rails_helper"

RSpec.describe Hub, type: :model do
  it "is valid with a name and unique code" do
    expect(build(:hub)).to be_valid
  end

  it "requires a unique code" do
    create(:hub, code: "HUB-DUP")
    expect(build(:hub, code: "HUB-DUP")).not_to be_valid
  end

  it "rejects a negative capacity" do
    expect(build(:hub, capacity: -1)).not_to be_valid
  end
end
