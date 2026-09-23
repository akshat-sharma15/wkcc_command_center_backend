require "rails_helper"

RSpec.describe AlertRuleEvaluator do
  describe "string field (default type)" do
    let(:vehicle) { create(:vehicle, status: "maintenance") }

    it "matches on =" do
      rule = build(:alert_rule, field: "status", operator: "=", value: "maintenance")
      expect(described_class.new(rule, vehicle).matches?).to eq(true)
    end

    it "does not match a different value on =" do
      rule = build(:alert_rule, field: "status", operator: "=", value: "active")
      expect(described_class.new(rule, vehicle).matches?).to eq(false)
    end

    it "matches on !=" do
      rule = build(:alert_rule, field: "status", operator: "!=", value: "active")
      expect(described_class.new(rule, vehicle).matches?).to eq(true)
    end

    it "matches on contains" do
      rule = build(:alert_rule, field: "status", operator: "contains", value: "mainten")
      expect(described_class.new(rule, vehicle).matches?).to eq(true)
    end
  end

  describe "numeric field" do
    let(:vehicle) { create(:vehicle, capacity: 5000) }

    it "matches on >" do
      rule = build(:alert_rule, field: "capacity", operator: ">", value: 1000)
      expect(described_class.new(rule, vehicle).matches?).to eq(true)
    end

    it "does not match on > when equal" do
      rule = build(:alert_rule, field: "capacity", operator: ">", value: 5000)
      expect(described_class.new(rule, vehicle).matches?).to eq(false)
    end

    it "matches on >=" do
      rule = build(:alert_rule, field: "capacity", operator: ">=", value: 5000)
      expect(described_class.new(rule, vehicle).matches?).to eq(true)
    end

    it "matches on <" do
      rule = build(:alert_rule, field: "capacity", operator: "<", value: 8000)
      expect(described_class.new(rule, vehicle).matches?).to eq(true)
    end

    it "matches numeric values given as strings" do
      rule = build(:alert_rule, field: "capacity", operator: "=", value: "5000")
      expect(described_class.new(rule, vehicle).matches?).to eq(true)
    end
  end

  describe "#actual_value" do
    it "returns the record's current field value as a string" do
      vehicle = create(:vehicle, status: "maintenance")
      rule = build(:alert_rule, field: "status")
      expect(described_class.new(rule, vehicle).actual_value).to eq("maintenance")
    end
  end
end
