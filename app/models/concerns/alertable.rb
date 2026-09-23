# Included by the five alertable business models (Vehicle, Hub, Package,
# PaymentDue, WorkforceMember — see AlertRule::ALERTABLE_MODELS; Trip is
# deliberately excluded). Detects a relevant change after the transaction
# commits and hands off to AlertEvaluationJob — this concern never
# evaluates rules, sends Slack/SSE, or does anything beyond "was an
# alertable field actually changed, if so enqueue a job." Using
# after_commit (not after_update) so the job never sees a record whose
# transaction later rolled back.
module Alertable
  extend ActiveSupport::Concern

  included do
    after_commit :enqueue_alert_evaluation, on: %i[create update]
  end

  class_methods do
    # The AlertRule::ALERTABLE_MODELS key for this class (e.g. "vehicles"
    # for Vehicle) — resolved lazily (inside a method body, not at class
    # load time) so this and AlertRule can reference each other without a
    # circular-load problem.
    def alertable_group_key
      @alertable_group_key ||= AlertRule::ALERTABLE_MODELS.key(self)
    end
  end

  private

  def enqueue_alert_evaluation
    return unless allow_alerts?

    changed_fields = previous_changes.keys & alertable_fields
    return if changed_fields.empty?

    AlertEvaluationJob.perform_async(self.class.alertable_group_key, id, changed_fields)
  end
end
