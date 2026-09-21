require "rails_helper"

RSpec.describe EventDefinition, type: :model do
  it "is valid with a matching group and type" do
    expect(build(:event_definition, group: "Fleet / Transport", event_type: "Accident")).to be_valid
  end

  it "requires a unique name" do
    create(:event_definition, name: "Truck Accident")
    expect(build(:event_definition, name: "Truck Accident")).not_to be_valid
  end

  it "rejects an unknown group" do
    expect(build(:event_definition, group: "Not A Group")).not_to be_valid
  end

  it "rejects a type that does not belong to the group" do
    event = build(:event_definition, group: "Hubs", event_type: "Accident")
    expect(event).not_to be_valid
    expect(event.errors[:event_type].join).to include("not valid for group")
  end

  it "accepts every documented group/type combination" do
    EventDefinition::GROUPS_AND_TYPES.each do |group, types|
      types.each do |type|
        event = build(:event_definition, name: "#{group}/#{type}", group: group, event_type: type)
        expect(event).to be_valid, "expected #{group} + #{type} to be valid: #{event.errors.full_messages}"
      end
    end
  end
end
