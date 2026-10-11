module CommandCenter
  # Gemini tools for the Fleet Map chat only. Each one answers from the SAME
  # code the map's own endpoints use (FleetMonitoring::HubVehicleFlow,
  # HubPresenter, VehiclePresenter), so the assistant's numbers and vehicle
  # lists are exactly what the map shows - not the reporting views, which
  # are scoped for the Superset dashboards.
  #
  # Read-only: every call runs inside a transaction marked
  # transaction_read_only (Postgres rejects any write) and is rolled back
  # afterwards. Arguments are only identifiers (hub code/name, vehicle
  # number, status) - never SQL.
  module MapTools
    STATEMENT_TIMEOUT_MS = 5_000
    MAX_VEHICLES = 200
    MAP_STATUSES = [
      FleetMonitoring::VehicleStatusResolver::STATUS_IN_TRANSIT,
      FleetMonitoring::VehicleStatusResolver::STATUS_PARKED,
      FleetMonitoring::VehicleStatusResolver::STATUS_MAINTENANCE,
      FleetMonitoring::VehicleStatusResolver::STATUS_DAMAGED
    ].freeze

    HUB_ARG = { type: "STRING", description: "Hub code (e.g. CC-HUB-018) or hub name (e.g. Nashik)." }.freeze

    DECLARATIONS = [
      {
        name: "map_hub_vehicles",
        description: "The vehicles the Fleet Map shows moving into (inbound) or out of (outbound) a hub right now - " \
                     "the exact list the map draws for the hub's inbound/outbound filter. Use for any 'inbound/outbound " \
                     "vehicles at <hub>' or 'trucks coming to/leaving <hub>' question.",
        parameters: {
          type: "OBJECT",
          properties: {
            hub: HUB_ARG,
            direction: { type: "STRING", enum: FleetMonitoring::HubVehicleFlow::DIRECTIONS, description: "inbound, outbound, or all (default all)." }
          },
          required: [ "hub" ]
        }
      },
      {
        name: "map_hub_summary",
        description: "A hub's card on the Fleet Map: status, capacity, parking, inbound/outbound vehicle counts, " \
                     "shipped/pending/defective/returned packages.",
        parameters: { type: "OBJECT", properties: { hub: HUB_ARG }, required: [ "hub" ] }
      },
      {
        name: "map_vehicle",
        description: "One vehicle as the Fleet Map shows it: map status, location, driver, vendor, capacity, current " \
                     "trip origin/destination, ETA and variance, diversion, active incident, waybills.",
        parameters: {
          type: "OBJECT",
          properties: { vehicle_number: { type: "STRING", description: "The vehicle number / PNR, e.g. MH12JI5781." } },
          required: [ "vehicle_number" ]
        }
      },
      {
        name: "map_fleet",
        description: "The Fleet Map's vehicles: counts by map status (IN TRANSIT, PARKED, MAINTENANCE, DAMAGED) and, " \
                     "when a status/city/state is given, the matching vehicles. Use for fleet-wide 'how many trucks are " \
                     "in transit / parked / in maintenance / in <city>' questions.",
        parameters: {
          type: "OBJECT",
          properties: {
            status: { type: "STRING", enum: MAP_STATUSES, description: "Only vehicles with this map status." },
            city: { type: "STRING", description: "Only vehicles currently in this city." },
            state: { type: "STRING", description: "Only vehicles currently in this state." }
          }
        }
      }
    ].freeze

    NAMES = DECLARATIONS.map { |d| d[:name] }.freeze

    def self.declarations
      DECLARATIONS
    end

    def self.handles?(name)
      NAMES.include?(name.to_s)
    end

    # Returns { payload: Hash } or { error: String }.
    def self.call(name, args)
      args = (args || {}).to_h.transform_keys(&:to_s)
      read_only { send(name.to_s, args) }
    end

    def self.read_only
      result = nil
      OperationsRecord.transaction(requires_new: true) do
        OperationsRecord.connection.execute("SET LOCAL transaction_read_only = on")
        OperationsRecord.connection.execute("SET LOCAL statement_timeout = #{STATEMENT_TIMEOUT_MS}")
        result = yield
        raise ActiveRecord::Rollback
      end
      result
    end

    def self.map_hub_vehicles(args)
      hub = find_hub(args["hub"]) or return hub_not_found(args["hub"])
      direction = FleetMonitoring::HubVehicleFlow::DIRECTIONS.include?(args["direction"]) ? args["direction"] : "all"
      vehicles = FleetMonitoring::HubVehicleFlow.scope(hub.id, direction)
                   .includes(vehicle: :current_geo_location, origin_hub: :geo_location, destination_hub: :geo_location)
                   .order(:id).map do |trip|
        row = FleetMonitoring::HubVehicleFlow.row(trip, hub)
        location = trip.vehicle.current_geo_location
        {
          vehicle_number: row[:vehicle_number], vehicle_type: trip.vehicle.vehicle_type, status: row[:status],
          direction: row[:direction], trip_id: row[:trip_id], origin_hub: row.dig(:origin, :name),
          destination_hub: row.dig(:destination, :name), current_city: location&.city, current_state: location&.state,
          eta: row[:eta]
        }
      end
      { payload: { hub: hub.name, hub_code: hub.code, direction: direction, count: vehicles.size, vehicles: vehicles } }
    end

    def self.map_hub_summary(args)
      hub = find_hub(args["hub"]) or return hub_not_found(args["hub"])
      { payload: FleetMonitoring::HubPresenter.new(hub).as_json.except(:lat, :lng) }
    end

    def self.map_vehicle(args)
      number = args["vehicle_number"].to_s.strip
      vehicle = Vehicle.fleet_monitoring_poc.includes(:current_geo_location, :vendor_account, :driver, hub: :geo_location)
                       .find_by("UPPER(number) = ?", number.upcase)
      return { error: "No vehicle #{number.inspect} on the Fleet Map." } unless vehicle

      trip = FleetMonitoring::VehiclePresenter.current_trip_for(vehicle)
      waybills = trip ? trip.waybills.order(:waybill_number).limit(50).pluck(:waybill_number) : []
      { payload: FleetMonitoring::VehiclePresenter.new(vehicle, current_trip: trip).as_json.merge(waybill_numbers: waybills) }
    end

    def self.map_fleet(args)
      vehicles = Vehicle.fleet_monitoring_poc.includes(:current_geo_location, :vendor_account, :driver, hub: :geo_location).order(:number).to_a
      context = FleetMonitoring::VehicleBatchContext.new(vehicles)
      presented = vehicles.map { |v| FleetMonitoring::VehiclePresenter.new(v, context: context, summary: true).as_json }

      counts = presented.group_by { |v| v[:status] }.transform_values(&:size)
      matching = presented
      matching = matching.select { |v| v[:status] == args["status"].to_s.upcase.tr("_", " ") } if args["status"].present?
      matching = matching.select { |v| v[:city].to_s.casecmp?(args["city"].to_s.strip) } if args["city"].present?
      matching = matching.select { |v| v[:state].to_s.casecmp?(args["state"].to_s.strip) } if args["state"].present?

      payload = { total_vehicles: presented.size, counts_by_status: counts }
      if args.values_at("status", "city", "state").any?(&:present?)
        payload[:matching_count] = matching.size
        payload[:vehicles] = matching.first(MAX_VEHICLES).map do |v|
          v.slice(:pnr, :status, :vehicle_type, :city, :state, :driver, :vendor, :trip_id, :diverted)
        end
      end
      { payload: payload }
    end

    def self.find_hub(key)
      key = key.to_s.strip
      return nil if key.blank?

      Hub.includes(:geo_location).find_by("UPPER(code) = ?", key.upcase) ||
        Hub.includes(:geo_location).where("name ILIKE ?", "%#{Hub.sanitize_sql_like(key)}%").order(:name).first
    end

    def self.hub_not_found(key)
      { error: "No hub matching #{key.to_s.inspect}." }
    end

    private_class_method :read_only, :map_hub_vehicles, :map_hub_summary, :map_vehicle, :map_fleet, :find_hub, :hub_not_found
  end
end
