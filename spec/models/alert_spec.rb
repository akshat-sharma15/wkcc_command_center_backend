require "rails_helper"

RSpec.describe Alert, type: :model do
  it "is valid with a name, event, role, and description" do
    expect(build(:alert)).to be_valid
  end

  it "requires an event definition" do
    expect(build(:alert, event_definition: nil)).not_to be_valid
  end

  it "requires a role" do
    expect(build(:alert, role: nil)).not_to be_valid
  end

  it "requires a description" do
    expect(build(:alert, description: nil)).not_to be_valid
  end
end
