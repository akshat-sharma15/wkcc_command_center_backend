# Builds the package shape truck_monitoring's app.js expects, bucketing
# Package's 6 real statuses down to the frontend's 3
# (IN TRANSIT / AT HUB / DELIVERED), and building `timeline` from the real
# package_status_transitions audit trail (falling back to a single
# "Order placed" entry from created_at for a package that hasn't
# transitioned yet). Warehouse-located packages are represented with their
# existing Warehouse#location string only - no Warehouse API/module is
# built here (out of scope for this POC).
module FleetMonitoring
  class PackagePresenter
    STATUS_MAP = {
      "in_transit" => "IN TRANSIT",
      "delivered" => "DELIVERED",
      "pending" => "AT HUB",
      "received" => "AT HUB",
      "damaged" => "AT HUB",
      "short" => "AT HUB"
    }.freeze

    def initialize(package)
      @package = package
    end

    def as_json(*)
      {
        id: @package.identifier,
        status: STATUS_MAP.fetch(@package.status, "AT HUB"),
        vehicle_pnr: in_transit_vehicle&.number,
        hub_code: hub_location&.code,
        current_location: current_location_label,
        destination: destination_label,
        expected_delivery: format_date(@package.promised_delivery_at),
        delivered_at: format_datetime(@package.delivered_at),
        timeline: timeline
      }
    end

    private

    def trip
      @package.trip
    end

    def in_transit_vehicle
      return nil unless trip&.status_in_transit?

      trip.vehicle
    end

    def hub_location
      @package.location if @package.location_type == "Hub"
    end

    def warehouse_location
      @package.location if @package.location_type == "Warehouse"
    end

    def current_location_label
      return in_transit_vehicle.current_geo_location&.city if in_transit_vehicle
      return hub_location.geo_location&.city || hub_location.location if hub_location
      return warehouse_location.location if warehouse_location

      nil
    end

    def destination_label
      destination_hub = trip&.destination_hub || @package.order&.destination_hub
      destination_hub&.name
    end

    def format_date(timestamp)
      timestamp&.strftime("%d %b %Y")
    end

    def format_datetime(timestamp)
      timestamp&.strftime("%d %b %Y · %H:%M")
    end

    def timeline
      transitions = @package.package_status_transitions.order(:occurred_at)
      return [fallback_entry] if transitions.empty?

      transitions.map do |transition|
        [transition.occurred_at.strftime("%d %b"), transition_label(transition), transition_place(transition)]
      end
    end

    def fallback_entry
      [@package.created_at.strftime("%d %b"), "Order placed", current_location_label || ""]
    end

    def transition_label(transition)
      STATUS_MAP.fetch(transition.to_status, transition.to_status.to_s.titleize)
    end

    def transition_place(transition)
      return "" unless transition.location_type && transition.location_id

      case transition.location_type
      when "Hub" then Hub.find_by(id: transition.location_id)&.name
      when "Warehouse" then Warehouse.find_by(id: transition.location_id)&.name
      end.to_s
    end
  end
end
