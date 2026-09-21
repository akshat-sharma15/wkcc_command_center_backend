require "rails_helper"

RSpec.describe Alert, type: :model do
  it "belongs to an AlertRule" do
    alert = create(:alert)
    expect(alert.alert_rule).to be_a(AlertRule)
  end

  it "is invalid without an alert_rule" do
    alert = build(:alert, alert_rule: nil, group: "vehicles", field: "status")
    expect(alert).not_to be_valid
  end

  it "defaults to open status" do
    expect(create(:alert).status).to eq("open")
  end
end
