# Announces a real-world OCCURRENCE of an EventDefinition ("this specific
# vehicle just failed") — distinct from EventDefinition itself, which is
# only the catalog/definition ("Vehicle Failure"). Deliberately does NOT
# persist an EventOccurrence table this phase; the published event is a
# plain in-memory call. Creates an Alert for every enabled AlertRule with
# trigger_type: "event" referencing the given EventDefinition, then hands
# off to the exact same AlertNotifier the condition pipeline uses — no
# separate/duplicated notification logic.
#
# `entity_type` is caller-supplied, free-text metadata ONLY. It is never
# constantized and has no relationship to AlertRule::ALERTABLE_MODELS
# (that registry is for condition-mode rules only) — an event rule can in
# principle be about anything, not just the five alertable business
# models.
class EventPublisher
  # Dedup key prefix for Alert#group, distinguishing event-triggered
  # Alerts from condition-triggered ones (whose #group is always one of
  # AlertRule::ALERTABLE_MODELS' keys, e.g. "vehicles" — never this
  # prefix) so the *existing* open-alert partial-unique-index naturally
  # also dedupes event alerts, scoped per (rule, entity_type, entity_id),
  # with no schema change needed. See the class doc below for the
  # semantics this produces.
  GROUP_PREFIX = "events:"

  class InvalidEvent < StandardError; end

  # Publishing the SAME event for the SAME entity while a previous
  # Alert for it is still open is treated as an accidental duplicate and
  # produces no second Alert (reuses the same open-alert uniqueness the
  # condition pipeline already has). Once that Alert is
  # acknowledged/resolved, publishing again creates a genuinely new Alert
  # — legitimate separate occurrences (e.g. the same vehicle failing again
  # next month) are never collapsed.
  def self.publish(event_definition:, entity_type:, entity_id:, payload: {})
    validate_event_definition!(event_definition)
    raise InvalidEvent, "entity_type is required" if entity_type.blank?
    raise InvalidEvent, "entity_id is required" if entity_id.blank?

    group = "#{GROUP_PREFIX}#{entity_type}"

    AlertRule.where(enabled: true, trigger_type: "event", event_definition_id: event_definition.id).find_each do |rule|
      next if Alert.exists?(alert_rule_id: rule.id, group: group, record_id: entity_id, status: "open")

      alert = create_alert(rule, event_definition, entity_type, entity_id, payload, group)
      AlertNotifier.notify(alert, rule)
    end
  end

  def self.validate_event_definition!(event_definition)
    return if event_definition.is_a?(EventDefinition) && EventDefinition.exists?(event_definition.id)

    raise InvalidEvent, "event_definition must be a persisted EventDefinition"
  end
  private_class_method :validate_event_definition!

  def self.create_alert(rule, event_definition, entity_type, entity_id, payload, group)
    Alert.create!(
      alert_rule: rule,
      group: group,
      record_id: entity_id,
      field: event_definition.event_type,
      severity: rule.severity,
      status: "open",
      triggered_at: Time.current,
      metadata: {
        event_definition_id: event_definition.id,
        event_definition_name: event_definition.name,
        entity_type: entity_type,
        entity_id: entity_id,
        payload: payload
      }
    )
  end
  private_class_method :create_alert
end
