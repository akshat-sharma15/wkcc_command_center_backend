# A triggered occurrence of an AlertRule against one specific business
# record (group + record_id, resolved via AlertRule::ALERTABLE_MODELS —
# never a direct FK, since the target varies by group). No automatic
# triggering exists yet (Phase 2+) — rows are only ever created manually
# for now.
class Alert < OperationsRecord
  enum :status, { open: "open", acknowledged: "acknowledged", resolved: "resolved" }, prefix: true

  belongs_to :alert_rule

  validates :group, presence: true
  validates :record_id, presence: true
  validates :field, presence: true
  validates :severity, presence: true
  validates :status, presence: true
  validates :triggered_at, presence: true
end
