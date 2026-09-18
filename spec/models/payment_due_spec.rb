require "rails_helper"

RSpec.describe PaymentDue, type: :model do
  it "is valid with a vendor, amount, and due_date" do
    expect(build(:payment_due)).to be_valid
  end

  it "requires a positive amount" do
    expect(build(:payment_due, amount: 0)).not_to be_valid
  end

  describe "#aging_days" do
    it "is 0 for a paid record" do
      payment_due = build(:payment_due, payment_status: "paid", due_date: 20.days.ago.to_date)
      expect(payment_due.aging_days).to eq(0)
    end

    it "counts days past due_date for an unpaid record" do
      payment_due = build(:payment_due, payment_status: "overdue", due_date: 5.days.ago.to_date)
      expect(payment_due.aging_days).to eq(5)
    end
  end
end
