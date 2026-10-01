# Builds the exact vehicle shape truck_monitoring's app.js/data.js expect
# (see the Fleet Monitoring API POC plan's "current truck_monitoring
# contract"). `pnr` is Vehicle#number - the frontend's "pnr" is the
# vehicle's own identifier, not a separate trip tracking number (there is
# no dedicated trip PNR field in the current frontend). `driver_phone`
# comes from WorkforceMember#phone_number, a POC-only column seeded with
# deterministic placeholder numbers (see db/seeds/fleet_monitoring_poc.rb)
# since no real phone data exists for these fictional seeded drivers.
module FleetMonitoring
  class VehiclePresenter
    # `context` (VehicleBatchContext) supplies preloaded per-vehicle data
    # for list endpoints; without it each lookup queries on demand.
    #
    # `summary:` (EMERGENCY PERF FIX, see PERFORMANCE.md) - true returns
    # just the marker fields the map's default (all-200-vehicles) view
    # needs, skipping the ETA/route/waybill computation that's only
    # meaningful for one selected vehicle/incident. Same field names as
    # the full payload so the frontend doesn't need two shapes, just
    # fewer of them populated.
    def initialize(vehicle, current_trip: nil, context: nil, summary: false)
      @vehicle = vehicle
      @context = context
      @summary = summary
      @current_trip = current_trip || (context ? context.current_trip(vehicle.id) : self.class.current_trip_for(vehicle))
    end

    def self.current_trip_for(vehicle)
      vehicle.trips.where(status: "in_transit").order(departure_at: :desc).first
    end

    def as_json(*)
      location = @vehicle.current_geo_location
      base = {
        pnr: @vehicle.number,
        lat: (location&.latitude || @vehicle.last_known_latitude)&.to_f,
        lng: (location&.longitude || @vehicle.last_known_longitude)&.to_f,
        city: location&.city,
        state: location&.state,
        vendor: @vehicle.vendor_account&.name || @vehicle.vendor,
        vendor_code: @vehicle.vendor_account&.code,
        capacity: capacity_label,
        capacity_kg: @vehicle.capacity,
        status: VehicleStatusResolver.resolve(@vehicle, current_trip: @current_trip),
        vehicle_type: @vehicle.vehicle_type,
        trip_status: @current_trip&.status,
        driver: @vehicle.driver&.name,
        vehicle_id: @vehicle.id,
        trip_id: @current_trip&.id,
        diverted: diversion.present?,
        diversion_id: diversion&.id,
        active_incident: active_incident
      }
      return base if @summary

      base.merge(
        occupied_capacity_kg: occupied_capacity_kg,
        available_capacity_kg: available_capacity_kg,
        capacity_utilization_pct: capacity_utilization_pct,
        fuel_efficiency_kmpl: @vehicle.fuel_efficiency_kmpl&.to_f,
        mileage_km: @vehicle.mileage_km&.to_f,
        origin: hub_point(@current_trip&.origin_hub),
        destination: hub_point(@current_trip&.destination_hub),
        eta: eta_label,
        driver_phone: @vehicle.driver&.phone_number,
        updated: updated_label,
        current_hub: hub_point(@current_trip ? @current_trip.origin_hub : @vehicle.hub),
        planned_eta: eta_impact&.planned_eta&.iso8601,
        predicted_eta: eta_impact&.predicted_eta&.iso8601,
        eta_variance_minutes: eta_impact&.eta_variance_minutes,
        eta_variance_label: DurationFormat.minutes(eta_impact&.eta_variance_minutes, signed: true),
        waybill_count: waybill_count
      )
    end

    private

    def capacity_label
      return nil if @vehicle.capacity.blank?

      "#{(@vehicle.capacity / 1000.0).round(1).to_s.sub(/\.0$/, '')} Ton"
    end

    def occupied_capacity_kg
      return 0 unless @current_trip
      return @context.occupied_capacity_kg(@current_trip.id) if @context

      # kg (Order#total_weight) actually loaded on the vehicle's current
      # trip - the only real weight figure the schema has today.
      @current_trip.packages.joins(:order).sum("orders.total_weight").to_f
    end

    def available_capacity_kg
      return nil if @vehicle.capacity.blank?

      [@vehicle.capacity.to_f - occupied_capacity_kg, 0].max
    end

    def capacity_utilization_pct
      return nil if @vehicle.capacity.blank? || @vehicle.capacity.zero?

      ((occupied_capacity_kg / @vehicle.capacity.to_f) * 100).round(1)
    end

    def diversion
      return @diversion if defined?(@diversion)

      @diversion = if @current_trip.nil? then nil
      elsif @context then @context.diversion(@current_trip.id)
      else @current_trip.route_diversions.active.order(:diverted_at).last
      end
    end

    def eta_impact
      return nil unless @current_trip

      @eta_impact ||= EtaImpactService.new(@current_trip, vehicle: @vehicle, diversion: diversion)
    end

    def waybill_count
      return 0 unless @current_trip

      @context ? @context.waybill_count(@current_trip.id) : @current_trip.waybills.open.count
    end

    def active_incident
      return @context.incident(@vehicle.id) if @context

      FleetMonitoring::VehicleBatchContext.new([ @vehicle ]).incident(@vehicle.id)
    end

    def hub_point(hub)
      return nil unless hub

      geo = hub.geo_location
      { name: hub.name, code: hub.code, state: geo&.state, lat: geo&.latitude&.to_f, lng: geo&.longitude&.to_f }
    end

    def eta_label
      return nil unless @current_trip&.expected_arrival_at

      remaining_minutes = ((@current_trip.expected_arrival_at - Time.current) / 60).round
      return "Arriving" if remaining_minutes <= 0

      DurationFormat.minutes(remaining_minutes)
    end

    def updated_label
      timestamp = @vehicle.last_location_at || @vehicle.updated_at
      minutes = ((Time.current - timestamp) / 60).round
      return "just now" if minutes < 1

      "#{DurationFormat.minutes(minutes)} ago"
    end
  end
end
