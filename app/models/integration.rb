# A connected third-party integration (currently only Slack). One row per
# provider — connecting/reconnecting updates the existing row rather than
# creating a duplicate (see Api::V1::SlackIntegrationsController#callback)
# since the product surface is "is Slack connected or not", not a list of
# historical connection attempts.
#
# `bot_token` is encrypted at rest via ActiveRecord::Encryption. It is
# never serialized in any API response (see IntegrationSerializer) and
# never logged.
class Integration < CommandCenterRecord
  PROVIDERS = %w[slack].freeze
  STATUSES = %w[connected disconnected].freeze

  encrypts :bot_token

  validates :provider, presence: true, uniqueness: true, inclusion: { in: PROVIDERS }
  validates :status, presence: true, inclusion: { in: STATUSES }

  def connected?
    status == "connected"
  end
end
