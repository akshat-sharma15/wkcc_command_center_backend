# A single (notification, recipient, channel) delivery record created
# when an Alert triggers and its rule has notify: true. `status` tracks
# the delivery pipeline; `read_at` tracks whether the recipient has seen
# it — two independent axes.
class Notification < OperationsRecord
  CHANNELS = %w[in_app slack].freeze
  STATUSES = %w[pending delivered failed].freeze

  belongs_to :alert

  validates :recipient_user_id, presence: true
  validates :channel, presence: true, inclusion: { in: CHANNELS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :for_recipient, ->(user_id) { where(recipient_user_id: user_id) }

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.current) unless read?
  end

  def mark_delivered!(external_reference: nil)
    update!(status: "delivered", delivered_at: Time.current, external_reference: external_reference, error_message: nil)
  end

  def mark_failed!(error_message)
    update!(status: "failed", failed_at: Time.current, error_message: error_message, attempts: attempts + 1)
  end
end
