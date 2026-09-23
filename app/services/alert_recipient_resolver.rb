# Resolves an AlertRule's recipient_type/recipient_id into a list of
# Superset user ids to notify. The only place that turns
# recipient_type/recipient_id into actual users — everything downstream
# (Notification creation) just takes a list of user ids.
#
# Never queries Superset directly — always through SupersetDirectory, and
# never copies/persists user data into the operations database.
class AlertRecipientResolver
  def initialize(alert_rule)
    @alert_rule = alert_rule
  end

  # Returns [] (not an error) when Superset isn't configured or the
  # recipient doesn't resolve — a rule that can't find recipients simply
  # produces no Notifications, same as notify: false. The caller can log
  # this distinctly from "notify: false" if it wants to (see
  # AlertEvaluationJob), but resolution itself never raises.
  def user_ids
    return [] unless @alert_rule.notify? && @alert_rule.recipient_type.present? && @alert_rule.recipient_id.present?
    return [] unless SupersetDirectory.configured?

    case @alert_rule.recipient_type
    when "role"
      SupersetDirectory.users_for_role(@alert_rule.recipient_id).map { |user| user[:id] }
    when "user"
      user = SupersetDirectory.find_user(@alert_rule.recipient_id)
      user ? [ user[:id] ] : []
    else
      []
    end
  end
end
