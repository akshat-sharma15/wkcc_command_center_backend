# Deterministic, route-consistent position for a Fleet Monitoring vehicle.
# Used by scripts/data/regenerate_vehicle_positions.rb (to place vehicles)
# and scripts/data/validate_operational_consistency.rb (to check them), so
# placement and validation share one definition of "where this vehicle
# should be".
#
#   on a current (in_transit) trip -> on its CURRENT route polyline
#     (EtaImpactService: origin -> via -> destination, or the diverted
#     path), at a fixed per-vehicle progress, with a small road-like
#     sideways offset that is zero at every waypoint (never an exact
#     straight line, never evenly spaced)
#   otherwise (parked / maintenance / out of service) -> in the yard area
#     around its home hub: 1-8 km out, denser close to the hub
#
# Every random choice comes from a Random seeded by the vehicle number, so
# the same vehicle always lands on the same spot.
module FleetMonitoring
  class VehiclePositionPlanner
    SEED_SALT = 20_260_929
    PROGRESS_RANGE = (0.08..0.92)
    MAX_SIDE_OFFSET_KM = 4.0
    YARD_RADIUS_KM = (1.0..8.0)
    PLANNING_SPEED_KMPH = 45.0 # pace used when a stale trip is re-anchored

    Plan = Struct.new(:lat, :lng, :progress, :path, :path_km, :mode, keyword_init: true)

    def self.rng_for(vehicle)
      Random.new(SEED_SALT ^ Zlib.crc32(vehicle.number))
    end

    def initialize(vehicle, trip: nil, diversion: :lookup)
      @vehicle = vehicle
      @trip = trip
      @diversion = diversion
    end

    def plan
      @plan ||= @trip ? on_route_plan : yard_plan
    end

    private

    def on_route_plan
      rng = self.class.rng_for(@vehicle)
      path = EtaImpactService.new(@trip, vehicle: @vehicle, diversion: @diversion).current_route
      progress = PROGRESS_RANGE.min + rng.rand * (PROGRESS_RANGE.max - PROGRESS_RANGE.min)
      side = (rng.rand * 2 - 1) * MAX_SIDE_OFFSET_KM
      point = point_along(path, progress, side)
      Plan.new(lat: point[:lat].round(6), lng: point[:lng].round(6), progress: progress, path: path,
               path_km: GeoDistance.path_km(path), mode: :route)
    end

    def yard_plan
      rng = self.class.rng_for(@vehicle)
      center = EtaImpactService.hub_point(@vehicle.hub) or return nil
      radius = YARD_RADIUS_KM.min + (YARD_RADIUS_KM.max - YARD_RADIUS_KM.min) * rng.rand**2 # denser near the hub
      angle = rng.rand * 2 * Math::PI
      point = offset(center, radius * Math.cos(angle), radius * Math.sin(angle))
      Plan.new(lat: point[:lat].round(6), lng: point[:lng].round(6), progress: nil, path: [ center ], path_km: 0, mode: :yard)
    end

    # Point at `fraction` of the polyline's length, pushed `side_km`
    # perpendicular to the current leg, scaled by sin(pi * t) so the
    # offset fades to zero at both ends of each leg.
    def point_along(path, fraction, side_km)
      target = GeoDistance.path_km(path) * fraction
      path.each_cons(2) do |from, to|
        leg = GeoDistance.km(from, to)
        if target <= leg || to.equal?(path.last)
          t = leg.zero? ? 0 : [ target / leg, 1.0 ].min
          base = { lat: coord(from, :lat) + (coord(to, :lat) - coord(from, :lat)) * t,
                   lng: coord(from, :lng) + (coord(to, :lng) - coord(from, :lng)) * t }
          return perpendicular(base, from, to, side_km * Math.sin(Math::PI * t))
        end
        target -= leg
      end
      path.last.symbolize_keys
    end

    def perpendicular(base, from, to, km)
      dx = (coord(to, :lng) - coord(from, :lng)) * Math.cos(coord(from, :lat) * Math::PI / 180) * 111.0
      dy = (coord(to, :lat) - coord(from, :lat)) * 111.0
      length = Math.hypot(dx, dy)
      return base if length.zero?

      offset(base, -dy / length * km, dx / length * km)
    end

    def offset(point, east_km, north_km)
      { lat: point[:lat] + north_km / 111.0,
        lng: point[:lng] + east_km / (111.0 * Math.cos(point[:lat] * Math::PI / 180)) }
    end

    def coord(point, key)
      (point[key] || point[key.to_s]).to_f
    end
  end
end
