class WorkforceMember < OperationsRecord
  include Alertable

  belongs_to :hub
  has_many :vehicles, foreign_key: :driver_id, inverse_of: :driver, dependent: :nullify

  enum :role_type, {
    guard: "guard",
    warehouse_worker: "warehouse_worker",
    loader: "loader",
    supervisor: "supervisor",
    driver: "driver",
    other_staff: "other_staff"
  }, prefix: true
  enum :attendance_status, { present: "present", absent: "absent", on_leave: "on_leave" }, prefix: true

  validates :identifier, presence: true, uniqueness: true
  validates :name, presence: true
end
