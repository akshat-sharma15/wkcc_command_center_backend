require "rails_helper"

RSpec.describe ApiClient, type: :model do
  describe "validations" do
    it "requires a name" do
      expect(build(:api_client, name: nil)).not_to be_valid
    end

    it "requires a unique name" do
      create(:api_client, name: "dup")
      duplicate = build(:api_client, name: "dup")
      expect(duplicate).not_to be_valid
    end
  end

  describe ".create_with_token!" do
    it "returns a persisted client and a raw token that is not stored" do
      client, raw_token = described_class.create_with_token!(name: "Simulator", scopes: ["events:write"])

      expect(client).to be_persisted
      expect(client.scopes).to eq(["events:write"])
      expect(raw_token).to be_present
      expect(client.token_digest).to eq(described_class.digest(raw_token))
      expect(client.token_digest).not_to eq(raw_token)
    end
  end

  describe ".authenticate" do
    it "finds the client for a valid, active token" do
      client, raw_token = described_class.create_with_token!(name: "Valid Client")
      expect(described_class.authenticate(raw_token)).to eq(client)
    end

    it "returns nil for an unknown token" do
      expect(described_class.authenticate("not-a-real-token")).to be_nil
    end

    it "returns nil for a deactivated client's token" do
      client, raw_token = described_class.create_with_token!(name: "Deactivated Client")
      client.update!(active: false)
      expect(described_class.authenticate(raw_token)).to be_nil
    end
  end

  describe "#has_scope?" do
    it "checks membership in the scopes array" do
      client = build(:api_client, scopes: ["vehicles:write"])
      expect(client.has_scope?("vehicles:write")).to be(true)
      expect(client.has_scope?("finance:write")).to be(false)
    end
  end
end
