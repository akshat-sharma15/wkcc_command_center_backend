# Derives the truck_monitoring frontend's 4-way vehicle status
# (IN TRANSIT / PARKED / MAINTENANCE / DAMAGED) from the existing
# `vehicles.status` enum (active/maintenance/out_of_service) plus whether
# the vehicle currently has an in_transit trip - the underlying enum alone
# can't distinguish "in transit" from "parked" (both are `active`), and has
# no maintenance/damaged equivalents. This is intentionally read-only and
# additive: it never writes to `vehicles.status`.
module FleetMonitoring
  class VehicleStatusResolver
    STATUS_IN_TRANSIT = "IN TRANSIT"
    STATUS_PARKED = "PARKED"
    STATUS_MAINTENANCE = "MAINTENANCE"
    STATUS_DAMAGED = "DAMAGED"

    def self.resolve(vehicle, current_trip: nil)
      return STATUS_MAINTENANCE if vehicle.status_maintenance?
      return STATUS_DAMAGED if vehicle.status_out_of_service?

      current_trip ? STATUS_IN_TRANSIT : STATUS_PARKED
    end
  end
end
