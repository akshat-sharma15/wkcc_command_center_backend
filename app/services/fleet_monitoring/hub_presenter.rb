# Builds the hub shape truck_monitoring's app.js expects. Metrics are
# computed from real associations (Hub#outbound_trips/inbound_trips/
# packages) rather than `hub_operations_events`, which has zero rows in
# every environment today (see db/operations_views/01_vw_hub_dashboard_
# summary.sql's own header comment) - using it here would just render as
# permanent zeros. `defectivePackages`/`returnedPackages` are the closest
# real Package#status concepts (damaged / short-shipped) to the frontend's
# labels - there is no literal "return" concept in the schema.
module FleetMonitoring
  class HubPresenter
    STATUS_MAP = {
      "active" => "OPERATIONAL",
      "degraded" => "HIGH LOAD",
      "closed" => "MAINTENANCE"
    }.freeze

    def initialize(hub)
      @hub = hub
    end

    def as_json(*)
      geo = @hub.geo_location
      {
        code: @hub.code,
        name: @hub.name,
        lat: geo&.latitude&.to_f,
        lng: geo&.longitude&.to_f,
        city: geo&.city,
        state: geo&.state,
        status: STATUS_MAP.fetch(@hub.operational_status, "OPERATIONAL"),
        capacity: @hub.capacity,
        parking_capacity: @hub.parking_capacity,
        available_parking: @hub.available_parking,
        inbound: inbound_count,
        outbound: outbound_count,
        shipped_today: shipped_count,
        pending_today: pending_count,
        defective_packages: defective_count,
        returned_packages: returned_count
      }
    end

    private

    def inbound_count
      @hub.inbound_trips.where(status: %w[in_transit completed]).count
    end

    def outbound_count
      @hub.outbound_trips.where(status: %w[in_transit completed]).count
    end

    def hub_packages
      @hub_packages ||= @hub.packages
    end

    def shipped_count
      hub_packages.status_delivered.count
    end

    def pending_count
      hub_packages.where(status: %w[pending received]).count
    end

    def defective_count
      hub_packages.status_damaged.count
    end

    def returned_count
      hub_packages.status_short.count
    end
  end
end
