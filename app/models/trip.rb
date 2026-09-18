class Trip < OperationsRecord
  belongs_to :vehicle
  belongs_to :origin_hub, class_name: "Hub"
  belongs_to :destination_hub, class_name: "Hub"
  has_many :packages, dependent: :nullify

  enum :status, {
    scheduled: "scheduled",
    in_transit: "in_transit",
    completed: "completed",
    cancelled: "cancelled",
    delayed: "delayed"
  }, prefix: true

  validate :destination_differs_from_origin

  private

  def destination_differs_from_origin
    return if origin_hub_id.blank? || destination_hub_id.blank?
    return if origin_hub_id != destination_hub_id

    errors.add(:destination_hub_id, "must differ from origin hub")
  end
end
