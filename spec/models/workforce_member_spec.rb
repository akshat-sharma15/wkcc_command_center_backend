require "rails_helper"

RSpec.describe WorkforceMember, type: :model do
  it "is valid with an identifier, name, role_type, and hub" do
    expect(build(:workforce_member)).to be_valid
  end

  it "requires a unique identifier" do
    create(:workforce_member, identifier: "WF-DUP")
    expect(build(:workforce_member, identifier: "WF-DUP")).not_to be_valid
  end

  it "requires a hub" do
    expect(build(:workforce_member, hub: nil)).not_to be_valid
  end
end
