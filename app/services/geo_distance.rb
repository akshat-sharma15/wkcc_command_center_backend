# Great-circle (haversine) distances over lat/lng waypoints. The schema has
# no road-network geometry, so every distance derived here is explicitly a
# straight-line-per-leg figure (callers label it `distance_basis:
# "great_circle"`); an operator-supplied road distance always takes
# precedence where a caller accepts one.
module GeoDistance
  EARTH_RADIUS_KM = 6371.0

  module_function

  def point?(point)
    point.respond_to?(:[]) && numeric?(fetch(point, :lat)) && numeric?(fetch(point, :lng))
  end

  def km(from, to)
    lat1, lng1 = coordinates(from)
    lat2, lng2 = coordinates(to)
    dlat = radians(lat2 - lat1)
    dlng = radians(lng2 - lng1)
    a = Math.sin(dlat / 2)**2 + Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dlng / 2)**2
    2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a))
  end

  def path_km(points)
    points.each_cons(2).sum { |from, to| km(from, to) }
  end

  def coordinates(point)
    [ fetch(point, :lat).to_f, fetch(point, :lng).to_f ]
  end

  def fetch(point, key)
    point[key] || point[key.to_s]
  end

  def radians(degrees)
    degrees * Math::PI / 180
  end

  def numeric?(value)
    value.is_a?(Numeric) || (value.is_a?(String) && value.match?(/\A-?\d+(\.\d+)?\z/))
  end
end
