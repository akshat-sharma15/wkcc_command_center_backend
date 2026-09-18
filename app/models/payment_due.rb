# Backs the "finance" domain (routed at /api/v1/finance).
class PaymentDue < OperationsRecord
  enum :payment_status, { pending: "pending", paid: "paid", overdue: "overdue" }, prefix: true

  validates :vendor, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :due_date, presence: true

  # Aging is derived, not stored, so it never goes stale relative to due_date.
  def aging_days
    return 0 if payment_status_paid?

    (Date.current - due_date).to_i.clamp(0, Float::INFINITY).to_i
  end
end
