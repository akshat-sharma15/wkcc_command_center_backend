# Preloads, in a fixed number of queries, everything VehiclePresenter would
# otherwise look up per vehicle (current trip, occupied weight, open
# waybills, active diversion, open incident). The fleet map lists every
# POC vehicle at once, so per-vehicle queries grow linearly with the fleet
# (~6 queries x 200 vehicles); this keeps the index at a constant ~6.
module FleetMonitoring
  class VehicleBatchContext
    SEVERITY_RANK = { "critical" => 0, "warning" => 1, "info" => 2 }.freeze

    def initialize(vehicles)
      @vehicle_ids = vehicles.map(&:id)
    end

    def current_trip(vehicle_id)
      current_trips[vehicle_id]
    end

    def occupied_capacity_kg(trip_id)
      occupied[trip_id] || 0.0
    end

    def waybill_count(trip_id)
      waybill_counts[trip_id] || 0
    end

    def diversion(trip_id)
      diversions[trip_id]
    end

    def incident(vehicle_id)
      incidents[vehicle_id]
    end

    private

    def current_trips
      @current_trips ||= Trip.where(vehicle_id: @vehicle_ids, status: "in_transit")
                             .includes(origin_hub: :geo_location, destination_hub: :geo_location)
                             .order(departure_at: :desc).to_a
                             .each_with_object({}) { |trip, by_vehicle| by_vehicle[trip.vehicle_id] ||= trip }
    end

    def trip_ids
      current_trips.values.map(&:id)
    end

    # Same figure as VehiclePresenter#occupied_capacity_kg.
    def occupied
      @occupied ||= Package.joins(:order).where(trip_id: trip_ids).group(:trip_id)
                           .sum("orders.total_weight").transform_values(&:to_f)
    end

    def waybill_counts
      @waybill_counts ||= Waybill.open.where(trip_id: trip_ids).group(:trip_id).count
    end

    def diversions
      @diversions ||= RouteDiversion.active.where(trip_id: trip_ids).order(:diverted_at).index_by(&:trip_id)
    end

    # Highest-severity unresolved alert about each vehicle: condition or
    # event alerts on the vehicle itself, or incidents whose snapshot
    # names it (e.g. a route diversion).
    def incidents
      @incidents ||= begin
        ids = @vehicle_ids.map(&:to_s)
        alerts = Alert.includes(:alert_rule).where.not(status: "resolved")
                      .where("(alerts.\"group\" IN (:groups) AND alerts.record_id IN (:ids)) " \
                             "OR (alerts.metadata -> 'incident' -> 'vehicle' ->> 'id') IN (:sids)", groups: %w[vehicles events:vehicles], ids: @vehicle_ids, sids: ids)
                      .to_a
        alerts.group_by { |alert| alert.metadata&.dig("incident", "vehicle", "id") || alert.record_id }
              .transform_keys(&:to_i)
              .transform_values do |list|
                top = list.min_by { |alert| [ SEVERITY_RANK.fetch(alert.severity, 9), -alert.triggered_at.to_i ] }
                { id: top.id, title: top.metadata&.dig("incident", "title") || top.alert_rule.name,
                  severity: top.severity, status: top.status, open_count: list.size }
              end
      end
    end
  end
end
