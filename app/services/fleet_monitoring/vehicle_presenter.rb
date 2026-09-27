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
    def initialize(vehicle, current_trip: nil)
      @vehicle = vehicle
      @current_trip = current_trip || self.class.current_trip_for(vehicle)
    end

    def self.current_trip_for(vehicle)
      vehicle.trips.where(status: "in_transit").order(departure_at: :desc).first
    end

    def as_json(*)
      location = @vehicle.current_geo_location
      {
        pnr: @vehicle.number,
        lat: (location&.latitude || @vehicle.last_known_latitude)&.to_f,
        lng: (location&.longitude || @vehicle.last_known_longitude)&.to_f,
        city: location&.city,
        state: location&.state,
        vendor: @vehicle.vendor_account&.name || @vehicle.vendor,
        vendor_code: @vehicle.vendor_account&.code,
        capacity: capacity_label,
        capacity_kg: @vehicle.capacity,
        occupied_capacity_kg: occupied_capacity_kg,
        available_capacity_kg: available_capacity_kg,
        capacity_utilization_pct: capacity_utilization_pct,
        status: VehicleStatusResolver.resolve(@vehicle, current_trip: @current_trip),
        vehicle_type: @vehicle.vehicle_type,
        fuel_efficiency_kmpl: @vehicle.fuel_efficiency_kmpl&.to_f,
        mileage_km: @vehicle.mileage_km&.to_f,
        origin: hub_point(@current_trip&.origin_hub),
        destination: hub_point(@current_trip&.destination_hub),
        eta: eta_label,
        trip_status: @current_trip&.status,
        driver: @vehicle.driver&.name,
        driver_phone: @vehicle.driver&.phone_number,
        updated: updated_label
      }
    end

    private

    def capacity_label
      return nil if @vehicle.capacity.blank?

      "#{(@vehicle.capacity / 1000.0).round(1).to_s.sub(/\.0$/, '')} Ton"
    end

    def occupied_capacity_kg
      return 0 unless @current_trip

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

    def hub_point(hub)
      return nil unless hub

      geo = hub.geo_location
      { name: hub.name, code: hub.code, state: geo&.state, lat: geo&.latitude&.to_f, lng: geo&.longitude&.to_f }
    end

    def eta_label
      return nil unless @current_trip&.expected_arrival_at

      remaining_minutes = ((@current_trip.expected_arrival_at - Time.current) / 60).round
      return "Arriving" if remaining_minutes <= 0

      "#{remaining_minutes / 60}h #{remaining_minutes % 60}m"
    end

    def updated_label
      timestamp = @vehicle.last_location_at || @vehicle.updated_at
      minutes = ((Time.current - timestamp) / 60).round
      return "just now" if minutes < 1

      "#{minutes} min ago"
    end
  end
end
