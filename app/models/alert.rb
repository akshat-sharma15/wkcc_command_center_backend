# An alert rule: which role gets notified when a given event definition
# fires. No Integration reference yet (Stage 3 scope is definition
# management only, not delivery) — that field is added in a later stage.
#
# `role` is a plain string for now. When the Superset roles lookup
# (GET /api/v1/superset/roles) lands, this stays a string (the role name)
# rather than an FK, since Superset's ab_role table lives in a different,
# read-only-accessed database that this app's associations must never cross
# into (see ARCHITECTURE.md).
class Alert < CommandCenterRecord
  belongs_to :event_definition

  validates :name, presence: true
  validates :role, presence: true
  validates :description, presence: true
end
