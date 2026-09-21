module Api
  module V1
    # Read-only metadata for the Alert Builder frontend: which groups
    # (business models), fields, and operators are available. Model
    # resolution always goes through AlertRule::ALERTABLE_MODELS — no
    # request param is ever constantized.
    class AlertResourcesController < BaseController
      GROUP_LABELS = {
        "vehicles" => "Vehicles",
        "hubs" => "Hubs",
        "packages" => "Packages",
        "payments" => "Payments",
        "workforce" => "Workforce"
      }.freeze

      # GET /api/v1/alert-resources
      def index
        groups = AlertRule::ALERTABLE_MODELS.keys.map do |key|
          { key: key, label: GROUP_LABELS.fetch(key, key.titleize) }
        end
        render json: groups
      end

      # GET /api/v1/alert-resources/:group/fields
      #
      # `allow_alerts`/`alertable_fields` are record-level configuration
      # (e.g. one specific Vehicle opting in), not model-level config, so
      # this returns the *union* of fields any record of the group has
      # opted in — the set of fields an AlertRule could legally target for
      # this group right now, matching AlertRule's own
      # field_must_be_alertable_on_target_model validation exactly.
      def fields
        return render_unsupported_group unless target_model

        alertable_columns = target_model.column_names.select do |column|
          target_model.where(allow_alerts: true).where("? = ANY (alertable_fields)", column).exists?
        end

        render json: alertable_columns.map { |column| field_metadata(column) }
      end

      # GET /api/v1/alert-resources/:group/fields/:field/options
      #
      # Only implemented for fields backed by a Rails enum (e.g.
      # Vehicle#status) — that is the one case this data model gives a
      # reliable finite list without scanning live data (which could be
      # empty or incomplete). Anything else returns 422, per "keep this
      # endpoint optional if the current data model does not provide a
      # reliable finite list."
      def field_options
        return render_unsupported_group unless target_model
        return render_unsupported_field unless alertable_field?(params[:field])

        enum_values = target_model.defined_enums[params[:field]]&.keys
        if enum_values.blank?
          return render json: { error: "Field '#{params[:field]}' has no finite set of options" },
            status: :unprocessable_content
        end

        render json: enum_values
      end

      private

      def target_model
        AlertRule::ALERTABLE_MODELS[params[:group]]
      end

      def alertable_field?(field)
        return false if field.blank? || !target_model.column_names.include?(field)

        target_model.where(allow_alerts: true).where("? = ANY (alertable_fields)", field).exists?
      end

      def field_metadata(column)
        {
          key: column,
          label: column.titleize,
          type: api_type_for(target_model.columns_hash[column].type),
          operators: AlertRule.operators_for(target_model, column)
        }
      end

      def api_type_for(column_type)
        case column_type
        when :integer, :float, :decimal then "number"
        when :boolean then "boolean"
        when :datetime, :date then "date"
        else "string"
        end
      end

      def render_unsupported_group
        render json: { error: "Unsupported group '#{params[:group]}'" }, status: :not_found
      end

      def render_unsupported_field
        render json: { error: "Field '#{params[:field]}' is not alertable for group '#{params[:group]}'" },
          status: :unprocessable_content
      end
    end
  end
end
