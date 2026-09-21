require "rails_helper"

RSpec.describe SupersetDirectory do
  describe ".configured?" do
    it "is false when the required env vars are not all present (this repository's current state)" do
      expect(described_class.configured?).to eq(false)
    end

    it "delegates to SupersetRecord.configured?" do
      expect(described_class.configured?).to eq(SupersetRecord.configured?)
    end
  end

  describe "read methods when not configured" do
    it "returns [] for roles and users, and nil for lookups, without attempting a connection" do
      expect(described_class.roles).to eq([])
      expect(described_class.users).to eq([])
      expect(described_class.find_role(1)).to be_nil
      expect(described_class.find_user(1)).to be_nil
      expect(described_class.users_for_role(1)).to eq([])
    end
  end

  describe "the underlying models are read-only" do
    # .allocate (not .new) deliberately, since .new would trigger schema
    # introspection against whatever connection the class currently has —
    # which is meaningless here anyway, since Superset isn't configured in
    # this environment. readonly? itself touches no attributes/DB.
    it "refuses to save a SupersetRole even if constructed directly" do
      expect(SupersetRole.allocate.readonly?).to eq(true)
    end

    it "refuses to save a SupersetUser even if constructed directly" do
      expect(SupersetUser.allocate.readonly?).to eq(true)
    end
  end
end
