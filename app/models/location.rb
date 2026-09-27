class Location < OperationsRecord
  has_many :vehicles, foreign_key: :current_location_id, inverse_of: :current_geo_location, dependent: :nullify
  has_many :hubs, foreign_key: :location_id, inverse_of: :geo_location, dependent: :nullify

  validates :city, :state, :country, presence: true
  validates :latitude, :longitude, presence: true, numericality: true
end
