# Read-only access to the operations database for the Command Centre AI
# chatbot's query service (see CommandCenter::QueryService), via a
# dedicated Postgres role (wkcc_ai_readonly) granted SELECT only on the
# approved views/tables and set default_transaction_read_only=on
# server-side (see config/database.yml's `ai_readonly` connection and
# docs/ai_readonly_role.sql) - so even a bug in app-level validation
# still cannot write. This is a genuinely separate DB credential from
# OperationsRecord, not just a different Rails class over the same one.
class AiReadOnlyRecord < ApplicationRecord
  self.abstract_class = true

  connects_to database: { writing: :ai_readonly, reading: :ai_readonly }

  # Defense in depth at the Rails layer too, on top of the Postgres-level
  # read-only transaction setting.
  def readonly?
    true
  end
end
