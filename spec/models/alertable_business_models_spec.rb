require "rails_helper"

# Covers the alert-configuration columns (allow_alerts/alertable_fields)
# shared by every model in AlertRule::ALERTABLE_MODELS, rather than
# repeating the same two assertions in each model's own spec file.
RSpec.describe "Alertable business models" do
  AlertRule::ALERTABLE_MODELS.each do |group, model_class|
    describe "#{model_class.name} (#{group})" do
      let(:record) { create(model_class.model_name.element.to_sym) }

      it "has allow_alerts defaulting to false" do
        expect(record.allow_alerts).to eq(false)
      end

      it "has alertable_fields defaulting to an empty array" do
        expect(record.alertable_fields).to eq([])
      end

      it "accepts allow_alerts and alertable_fields" do
        record.update!(allow_alerts: true, alertable_fields: %w[status])
        expect(record.reload.allow_alerts).to eq(true)
        expect(record.reload.alertable_fields).to eq(%w[status])
      end
    end
  end
end
