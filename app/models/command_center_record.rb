# Base class for the command_center database (events, alert rules,
# integrations, notifications). Empty schema until Stage 3+ — this class
# exists now so the third database connection is proven wired end-to-end
# (see Api::V1::HealthController) rather than rediscovered later.
class CommandCenterRecord < ApplicationRecord
  self.abstract_class = true

  connects_to database: { writing: :command_center, reading: :command_center }
end
