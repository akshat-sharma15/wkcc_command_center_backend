# Enforces "only one open Alert per (alert_rule_id, group, record_id)" at
# the database level (a partial unique index, Postgres-native) rather than
# relying solely on application-level find-then-create logic, which is
# race-prone under concurrent AlertEvaluationJob runs for the same record.
class AddOpenAlertUniqueness < ActiveRecord::Migration[8.1]
  def change
    add_index :alerts, %i[alert_rule_id group record_id],
      unique: true,
      where: "status = 'open'",
      name: "index_alerts_on_open_rule_group_record"
  end
end
