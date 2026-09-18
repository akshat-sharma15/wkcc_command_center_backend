module Api
  module V1
    class PaymentDueSerializer
      def initialize(payment_due)
        @payment_due = payment_due
      end

      def as_json(*)
        {
          id: @payment_due.id,
          vendor: @payment_due.vendor,
          amount: @payment_due.amount,
          due_date: @payment_due.due_date,
          payment_status: @payment_due.payment_status,
          aging_days: @payment_due.aging_days,
          created_at: @payment_due.created_at,
          updated_at: @payment_due.updated_at
        }
      end
    end
  end
end
