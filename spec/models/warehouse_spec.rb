require "rails_helper"

RSpec.describe Warehouse, type: :model do
  it "is valid with a name and unique code" do
    expect(build(:warehouse)).to be_valid
  end

  it "requires a unique code" do
    create(:warehouse, code: "WH-DUP")
    expect(build(:warehouse, code: "WH-DUP")).not_to be_valid
  end
end
