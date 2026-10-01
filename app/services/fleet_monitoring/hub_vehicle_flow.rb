# THE single definition of "vehicles inbound to / outbound from a hub" for
# the fleet map. Hub hover counts (HubPresenter), the hub vehicle list
# (map inbound/outbound filter) and the vehicle-summary endpoint all read
# from #scope, so a count can never disagree with the vehicles drawn.
#
# A vehicle is in a hub's flow when it is a Fleet Monitoring POC vehicle
# (the map's fleet) and its CURRENT trip - its latest in_transit trip,
# the same trip VehiclePresenter shows - ends at the hub (inbound) or
# starts there (outbound).
module FleetMonitoring
  class HubVehicleFlow
    DIRECTIONS = %w[all inbound outbound].freeze

    # Current trips of map vehicles: one (the latest in_transit) per vehicle.
    def self.current_trips
      latest_ids = Trip.status_in_transit.joins(:vehicle).merge(Vehicle.fleet_monitoring_poc)
                       .select("DISTINCT ON (trips.vehicle_id) trips.id")
                       .order("trips.vehicle_id, trips.departure_at DESC NULLS LAST, trips.id DESC")
      Trip.where(id: latest_ids)
    end

    def self.scope(hub_id, direction)
      raise ArgumentError, "direction must be one of #{DIRECTIONS.join(', ')}" unless DIRECTIONS.include?(direction)

      trips = current_trips
      case direction
      when "inbound" then trips.where(destination_hub_id: hub_id)
      when "outbound" then trips.where(origin_hub_id: hub_id)
      else trips.where(destination_hub_id: hub_id).or(trips.where(origin_hub_id: hub_id))
      end
    end

    # { hub_id => { inbound:, outbound: } } for every hub, in two grouped
    # queries over the same current_trips relation as .scope.
    def self.counts_by_hub
      inbound = current_trips.group(:destination_hub_id).count
      outbound = current_trips.group(:origin_hub_id).count
      (inbound.keys | outbound.keys).index_with { |id| { inbound: inbound.fetch(id, 0), outbound: outbound.fetch(id, 0) } }
    end

    def self.summary(hub)
      inbound = scope(hub.id, "inbound").count
      outbound = scope(hub.id, "outbound").count
      { hub_id: hub.id, hub_code: hub.code, inbound_count: inbound, outbound_count: outbound, total_count: scope(hub.id, "all").count }
    end

    def self.rows(hub, direction)
      scope(hub.id, direction)
        .includes(vehicle: :current_geo_location, origin_hub: :geo_location, destination_hub: :geo_location)
        .order(:id).map { |trip| row(trip, hub) }
    end

    def self.row(trip, hub)
      vehicle = trip.vehicle
      location = vehicle.current_geo_location
      origin = EtaImpactService.hub_point(trip.origin_hub)
      destination = EtaImpactService.hub_point(trip.destination_hub)
      {
        vehicle_id: vehicle.id,
        pnr: vehicle.number,
        vehicle_number: vehicle.number,
        lat: (location&.latitude || vehicle.last_known_latitude)&.to_f,
        lng: (location&.longitude || vehicle.last_known_longitude)&.to_f,
        status: VehicleStatusResolver.resolve(vehicle, current_trip: trip),
        direction: trip.destination_hub_id == hub.id ? "inbound" : "outbound",
        hub_code: hub.code,
        trip_id: trip.id,
        route: [ origin&.dig(:name), destination&.dig(:name) ].compact.join(" → "),
        origin: origin,
        destination: destination,
        eta: trip.expected_arrival_at&.iso8601
      }
    end
  end
end
