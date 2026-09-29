require "rails_helper"

RSpec.describe AlertRule, "assignees", type: :model do
  it "accepts primary and secondary assignees" do
    rule = create(:alert_rule, primary_assignee_type: "user", primary_assignee_id: 1,
                              secondary_assignee_type: "role", secondary_assignee_id: 2, escalation_after_minutes: 30)
    expect(rule).to be_persisted
    expect(rule.assignee_for(:secondary)).to eq(type: "role", id: 2)
  end

  it "requires type and id together, a known type, and a primary before a secondary" do
    expect(build(:alert_rule, primary_assignee_type: "user")).not_to be_valid
    expect(build(:alert_rule, primary_assignee_type: "team", primary_assignee_id: 1)).not_to be_valid
    expect(build(:alert_rule, secondary_assignee_type: "user", secondary_assignee_id: 1)).not_to be_valid
    expect(build(:alert_rule, escalation_after_minutes: 0)).not_to be_valid
  end
end
