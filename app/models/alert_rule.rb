# A condition template ("vehicles.status = FAILURE at critical severity")
# that Phase 3+ will evaluate against real records and turn into Alerts.
# No triggering/evaluation logic exists yet — this is data-layer +
# metadata-API only (Phase 2).
class AlertRule < OperationsRecord
  # Server-side allowlist of alertable models. Deliberately not
  # AlertResource/AlertResourceField tables — this is an application-level
  # security boundary, not database data, so frontend input is never
  # constantized directly (see #target_model).
  # No "routes" entry — there is no Route (or equivalent) business model
  # independent of alerting; Trip is explicitly excluded (see
  # AddAlertConfigurationToBusinessModels), so "routes" has nothing valid
  # to point at until a real Route/lane entity is justified on its own.
  ALERTABLE_MODELS = {
    "vehicles" => Vehicle,
    "hubs" => Hub,
    "packages" => Package,
    "payments" => PaymentDue,
    "workforce" => WorkforceMember
  }.freeze

  SEVERITIES = %w[info warning critical].freeze
  RECIPIENT_TYPES = %w[role user].freeze
  NOTIFICATION_CHANNELS = %w[in_app email slack].freeze

  # Which comparison operators are meaningful for a given ActiveRecord
  # column type. The single source of truth for operator validity — both
  # this model's own validation and Api::V1::AlertResourcesController's
  # field metadata read from here, so the API can never advertise an
  # operator the model would then reject.
  OPERATORS_BY_TYPE = {
    numeric: %w[= != > < >= <=],
    boolean: %w[= !=],
    default: %w[= != contains]
  }.freeze
  NUMERIC_COLUMN_TYPES = %i[integer float decimal].freeze

  has_many :alerts, dependent: :restrict_with_error
  belongs_to :event_definition, optional: true

  validates :name, presence: true
  validates :group, presence: true, inclusion: { in: ALERTABLE_MODELS.keys, allow_blank: true }
  validates :field, presence: true
  validates :operator, presence: true
  validates :severity, presence: true, inclusion: { in: SEVERITIES, allow_blank: true }
  validates :recipient_type, inclusion: { in: RECIPIENT_TYPES, allow_blank: true }
  validates :recipient_type, presence: true, if: :notify?
  validates :recipient_id, presence: true, if: :notify?

  validate :field_must_exist_on_target_model
  validate :field_must_be_alertable_on_target_model
  validate :operator_must_be_valid_for_field_type
  validate :value_must_match_field_type
  validate :notification_channels_must_be_supported
  validate :recipient_must_exist_in_superset
  validate :event_definition_must_exist_if_given

  # The actual model class for this rule's group, via the allowlist above —
  # never Object.const_get/constantize on the raw `group` string.
  def target_model
    ALERTABLE_MODELS[group]
  end

  # Operators valid for `field`'s actual column type on `model`. Returns
  # [] for an unrecognized model/field rather than raising, since callers
  # (the fields API) need a safe empty result for an invalid combination.
  def self.operators_for(model, field)
    return [] if model.nil? || field.blank? || !model.column_names.include?(field.to_s)

    OPERATORS_BY_TYPE.fetch(column_type_category(model, field), OPERATORS_BY_TYPE[:default])
  end

  def self.column_type_category(model, field)
    column_type = model.columns_hash[field.to_s].type
    return :numeric if NUMERIC_COLUMN_TYPES.include?(column_type)
    return :boolean if column_type == :boolean

    :default
  end

  private

  def field_must_exist_on_target_model
    return if target_model.nil? || field.blank?

    errors.add(:field, "is not a column on #{target_model.name}") unless target_model.column_names.include?(field)
  end

  def field_must_be_alertable_on_target_model
    return if target_model.nil? || field.blank?
    return unless target_model.column_names.include?(field)

    alertable = target_model.where(allow_alerts: true).where("? = ANY (alertable_fields)", field).exists?
    errors.add(:field, "is not marked alertable on any #{target_model.name} record") unless alertable
  end

  def operator_must_be_valid_for_field_type
    return if target_model.nil? || field.blank? || operator.blank?
    return unless target_model.column_names.include?(field)

    allowed = self.class.operators_for(target_model, field)
    errors.add(:operator, "'#{operator}' is not valid for field '#{field}'") unless allowed.include?(operator)
  end

  # "Where practical" per spec — a light type sanity check, not full
  # coercion. String/text fields accept anything (including "contains").
  def value_must_match_field_type
    return if target_model.nil? || field.blank? || value.nil?
    return unless target_model.column_names.include?(field)

    case self.class.column_type_category(target_model, field)
    when :numeric
      errors.add(:value, "must be numeric for field '#{field}'") unless numeric_value?
    when :boolean
      errors.add(:value, "must be true or false for field '#{field}'") unless [ true, false ].include?(value)
    end
  end

  def numeric_value?
    Float(value.to_s)
    true
  rescue ArgumentError, TypeError
    false
  end

  def notification_channels_must_be_supported
    return if notification_channels.blank?

    unsupported = notification_channels - NOTIFICATION_CHANNELS
    return if unsupported.empty?

    errors.add(:notification_channels, "contains unsupported values: #{unsupported.join(', ')}")
  end

  # Only enforced when Superset is actually configured (see
  # SupersetDirectory) — this repository has no real Superset connection,
  # so recipient_id is otherwise trusted as an opaque reference for now.
  def recipient_must_exist_in_superset
    return unless notify? && recipient_type.present? && recipient_id.present?
    return unless SupersetDirectory.configured?
    return unless RECIPIENT_TYPES.include?(recipient_type)

    exists = case recipient_type
    when "role" then SupersetDirectory.find_role(recipient_id).present?
    when "user" then SupersetDirectory.find_user(recipient_id).present?
    end

    errors.add(:recipient_id, "does not exist in Superset") unless exists
  end

  # belongs_to :event_definition, optional: true skips presence entirely,
  # so a bogus id would otherwise only surface as a raw FK violation at
  # save time rather than a clean validation error.
  def event_definition_must_exist_if_given
    return if event_definition_id.blank?

    errors.add(:event_definition_id, "does not exist") unless EventDefinition.exists?(event_definition_id)
  end
end
