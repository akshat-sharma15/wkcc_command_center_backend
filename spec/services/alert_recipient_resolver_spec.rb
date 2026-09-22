require "rails_helper"

RSpec.describe AlertRecipientResolver do
  it "returns [] when notify is false" do
    rule = build(:alert_rule, notify: false, recipient_type: "role", recipient_id: 5)
    expect(described_class.new(rule).user_ids).to eq([])
  end

  it "returns [] when Superset is not configured (this repository's current state)" do
    expect(SupersetDirectory.configured?).to eq(false)
    rule = build(:alert_rule, notify: true, recipient_type: "role", recipient_id: 5)
    expect(described_class.new(rule).user_ids).to eq([])
  end

  context "when Superset is configured" do
    before { allow(SupersetDirectory).to receive(:configured?).and_return(true) }

    it "resolves a role recipient to every user in that role" do
      allow(SupersetDirectory).to receive(:users_for_role).with(5).and_return(
        [ { id: 10, name: "Alice" }, { id: 11, name: "Bob" } ]
      )
      rule = build(:alert_rule, notify: true, recipient_type: "role", recipient_id: 5)

      expect(described_class.new(rule).user_ids).to contain_exactly(10, 11)
    end

    it "resolves a user recipient to that single user" do
      allow(SupersetDirectory).to receive(:find_user).with(7).and_return({ id: 7, name: "Carol" })
      rule = build(:alert_rule, notify: true, recipient_type: "user", recipient_id: 7)

      expect(described_class.new(rule).user_ids).to eq([ 7 ])
    end

    it "returns [] when the user recipient does not resolve" do
      allow(SupersetDirectory).to receive(:find_user).with(999).and_return(nil)
      rule = build(:alert_rule, notify: true, recipient_type: "user", recipient_id: 999)

      expect(described_class.new(rule).user_ids).to eq([])
    end
  end
end
