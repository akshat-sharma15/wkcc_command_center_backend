# A road path between a route's waypoints (origin hub -> via -> destination
# hub), as Google's encoded polyline. See FleetMonitoring::RoadRouteService.
class RoadRoute < ApplicationRecord
  # Stored routes are refreshed after this long rather than kept forever.
  MAX_AGE = 30.days

  validates :route_key, :encoded_polyline, :fetched_at, presence: true

  scope :fresh, -> { where("fetched_at > ?", MAX_AGE.ago) }

  # Waypoints rounded to ~1 m, so the same route always gets the same key.
  def self.key_for(waypoints)
    Digest::SHA256.hexdigest(waypoints.map { |p| format("%.5f,%.5f", p[:lat].to_f, p[:lng].to_f) }.join("|"))
  end

  def fresh?
    fetched_at > MAX_AGE.ago
  end
end
