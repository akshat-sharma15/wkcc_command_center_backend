# Enqueued by the Alertable concern after a relevant field changes.
# Resolves the model ONLY via AlertRule::ALERTABLE_MODELS (never
# constantizes `group`), evaluates matching enabled CONDITION rules, and
# creates/resolves Alerts. Never handles trigger_type: "event" rules —
# those fire only via EventPublisher.publish. Never sends Slack/SSE
# directly — that's NotificationDeliveryJob's job (via AlertNotifier),
# enqueued separately so a Slack outage can never block or roll back
# Alert creation.
class AlertEvaluationJob < ApplicationJob
  def perform(group, record_id, changed_fields)
    model = AlertRule::ALERTABLE_MODELS[group]
    return unless model

    record = model.find_by(id: record_id)
    return unless record&.allow_alerts?

    # Re-check against the record's *current* alertable_fields (not just
    # what it was when this job was enqueued) — cheap, and closes the
    # race window where alertable_fields changed in between.
    relevant_fields = changed_fields & record.alertable_fields
    return if relevant_fields.empty?

    AlertRule.where(enabled: true, trigger_type: "condition", group: group, field: relevant_fields)
      .find_each { |rule| evaluate_rule(rule, record) }
  end

  private

  def evaluate_rule(rule, record)
    evaluator = AlertRuleEvaluator.new(rule, record)
    open_alert = Alert.find_by(alert_rule_id: rule.id, group: rule.group, record_id: record.id, status: "open")

    if evaluator.matches?
      return if open_alert

      alert = create_alert(rule, record, evaluator)
      AlertNotifier.notify(alert, rule) if alert
    elsif open_alert
      open_alert.update!(status: "resolved", resolved_at: Time.current)
    end
  end

  # A DB-level partial unique index (open alerts only) backs this up
  # against concurrent AlertEvaluationJob runs for the same record/rule —
  # if we lose that race, the other job's Alert is the one that exists,
  # which is exactly the desired outcome, not an error.
  def create_alert(rule, record, evaluator)
    Alert.create!(
      alert_rule: rule,
      group: rule.group,
      record_id: record.id,
      field: rule.field,
      expected_value: rule.value.to_s,
      actual_value: evaluator.actual_value,
      severity: rule.severity,
      status: "open",
      triggered_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
