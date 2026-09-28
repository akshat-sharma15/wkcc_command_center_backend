# Builds a consistent title/message/metadata for an Alert, reused for
# both in_app and Slack delivery, for BOTH trigger modes. Deliberately has
# no per-model or per-event-type text — the entity label is derived by
# reflection (checking a few common identifying attribute names in order)
# so a new alertable model, or a new kind of published event, needs no
# change here.
class AlertNotificationMessageBuilder
  IDENTIFYING_ATTRIBUTES = %w[number identifier name code vendor].freeze

  def initialize(alert)
    @alert = alert
    @alert_rule = alert.alert_rule
  end

  # The rule's own name IS the intended title — that's what the `name`
  # field on AlertRule is for.
  def title
    @alert_rule.name
  end

  def message
    if @alert_rule.event_trigger?
      "#{entity_label} triggered #{@alert.metadata['event_definition_name'] || 'an event'}."
    else
      "#{entity_label} has #{@alert.field.humanize.downcase} #{@alert.actual_value}."
    end
  end

  def metadata
    base = {
      alert_id: @alert.id,
      alert_rule_id: @alert_rule.id,
      rule_name: @alert_rule.name,
      trigger_type: @alert_rule.trigger_type,
      severity: @alert.severity,
      record_id: @alert.record_id,
      triggered_at: @alert.triggered_at&.iso8601
    }

    if @alert_rule.event_trigger?
      base.merge(@alert.metadata || {})
    else
      base.merge(
        group: @alert.group,
        field: @alert.field,
        expected_value: @alert.expected_value,
        actual_value: @alert.actual_value
      )
    end
  end

  private

  def entity_label
    if @alert_rule.event_trigger?
      entity_type = @alert.metadata&.dig("entity_type") || "Entity"
      return named_event_entity_label(entity_type) || "#{entity_type} ##{@alert.record_id}"
    end

    model = AlertRule::ALERTABLE_MODELS[@alert.group]
    model_name = model&.model_name&.human || @alert.group.to_s.singularize.humanize
    record = model&.find_by(id: @alert.record_id)
    return "#{model_name} ##{@alert.record_id}" unless record

    identifying_attribute = IDENTIFYING_ATTRIBUTES.find do |attr|
      record.respond_to?(attr) && record.public_send(attr).present?
    end
    return "#{model_name} ##{@alert.record_id}" unless identifying_attribute

    prefixed_label(model_name, record.public_send(identifying_attribute))
  end

  # Avoids "Hub Bhopal North Hub" when the identifying value (e.g. a Hub's
  # own `name`) already contains the model name as a word, anywhere in it.
  def prefixed_label(model_name, value)
    value.to_s.match?(/\b#{Regexp.escape(model_name)}\b/i) ? value.to_s : "#{model_name} #{value}"
  end

  # Best-effort upgrade for event-triggered alerts only: if the caller's
  # free-text entity_type happens to match one of the known alertable
  # models (e.g. "hubs", "vehicles"), resolve the real record's name for a
  # readable label ("Indore Regional Hub" instead of "Hub #1"). Returns
  # nil on any mismatch so the caller's generic fallback still applies —
  # entity_type remains free text with no required relationship to
  # ALERTABLE_MODELS.
  def named_event_entity_label(entity_type)
    model = AlertRule::ALERTABLE_MODELS[entity_type.to_s.downcase]
    return nil unless model

    record = model.find_by(id: @alert.record_id)
    return nil unless record

    identifying_attribute = IDENTIFYING_ATTRIBUTES.find do |attr|
      record.respond_to?(attr) && record.public_send(attr).present?
    end
    return nil unless identifying_attribute

    prefixed_label(model.model_name.human, record.public_send(identifying_attribute))
  end
end
