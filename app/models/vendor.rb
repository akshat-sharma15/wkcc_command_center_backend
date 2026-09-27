class Vendor < OperationsRecord
  has_many :vehicles, foreign_key: :vendor_id, inverse_of: :vendor_account, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :code, presence: true, uniqueness: true
end
