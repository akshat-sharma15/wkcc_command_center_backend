# Filtering + summary for RouteDiversions, shared by GET
# /api/v1/route-diversions, /route-diversions/summary and the map's
# diverted-routes layer, so a summary always describes exactly the rows
# the list returns.
#
# Filters: status (default "active"; "all" for every status), vehicle
# (id or number), hub (id or code; origin OR destination of the diverted
# trip), region (state of either trip hub), from/to (diverted_at).
class RouteDiversionQuery
  def initialize(params = {})
    @params = params.to_h.with_indifferent_access
  end

  def scope
    relation = RouteDiversion.left_joins(trip: [ { origin_hub: :geo_location }, { destination_hub: :geo_location } ]).joins(:vehicle)
    status = @params[:status].presence || "active"
    relation = relation.where(status: status) unless status == "all"
    relation = relation.where(vehicles: { number: @params[:vehicle] }).or(relation.where(vehicle_id: integer(@params[:vehicle]))) if @params[:vehicle].present?
    if @params[:hub].present?
      hub_ids = Hub.where(code: @params[:hub]).or(Hub.where(id: integer(@params[:hub]))).select(:id)
      relation = relation.where(trips: { origin_hub_id: hub_ids }).or(relation.where(trips: { destination_hub_id: hub_ids }))
    end
    if @params[:region].present?
      relation = relation.where("locations.state = :r OR geo_locations_hubs.state = :r", r: @params[:region])
    end
    relation = relation.where(diverted_at: Time.zone.parse(@params[:from])..) if @params[:from].present?
    relation = relation.where(diverted_at: ..Time.zone.parse(@params[:to])) if @params[:to].present?
    relation.distinct
  end

  # Aggregates over #scope. revenue_risk is nil (with a reason) when no
  # diversion in scope has a calculable revenue risk - never a guess.
  def summary
    rows = scope.includes(:trip).to_a
    risks = rows.filter_map(&:revenue_risk)
    {
      diverted_routes: rows.map { |d| [ d.trip.origin_hub_id, d.trip.destination_hub_id ] }.uniq.size,
      diverted_trips: rows.map(&:trip_id).uniq.size,
      diverted_vehicles: rows.map(&:vehicle_id).uniq.size,
      affected_waybills: rows.sum { |d| d.affected_waybills.to_i },
      affected_orders: rows.sum { |d| d.affected_orders.to_i },
      affected_packages: rows.sum { |d| d.affected_packages.to_i },
      additional_distance_km: rows.sum { |d| d.additional_distance_km.to_f }.round(2),
      revenue_risk: risks.any? ? risks.sum.to_f.round(2) : nil,
      revenue_risk_unavailable: risks.any? ? nil : (rows.any? ? "no_calculable_revenue_risk" : nil),
      filters: @params.slice(:status, :vehicle, :hub, :region, :from, :to).merge(status: @params[:status].presence || "active")
    }
  end

  private

  def integer(value)
    Integer(value.to_s, exception: false)
  end
end
