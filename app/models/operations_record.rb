class OperationsRecord < ApplicationRecord
  self.abstract_class = true

  connects_to database: { writing: :operations, reading: :operations }
end
