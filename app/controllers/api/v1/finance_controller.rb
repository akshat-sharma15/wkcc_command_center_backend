module Api
  module V1
    # Backs the "finance" domain (PaymentDue records), routed at /api/v1/finance
    # since the model name and URL segment differ.
    class FinanceController < BaseController
      before_action :set_payment_due, only: %i[show update destroy]

      def index
        pagy, payment_dues = pagy(PaymentDue.order(due_date: :asc))
        response.headers.merge!(pagy_headers_merge(pagy))
        render json: payment_dues.map { |p| PaymentDueSerializer.new(p).as_json }
      end

      def show
        render json: PaymentDueSerializer.new(@payment_due).as_json
      end

      def create
        payment_due = PaymentDue.new(payment_due_params)
        payment_due.save!
        render json: PaymentDueSerializer.new(payment_due).as_json, status: :created
      end

      def update
        @payment_due.update!(payment_due_params)
        render json: PaymentDueSerializer.new(@payment_due).as_json
      end

      def destroy
        @payment_due.destroy!
        head :no_content
      end

      private

      def set_payment_due
        @payment_due = PaymentDue.find(params[:id])
      end

      def payment_due_params
        params.require(:payment_due).permit(:vendor, :amount, :due_date, :payment_status)
      end
    end
  end
end
