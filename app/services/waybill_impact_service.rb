# Which consignments a disrupted trip affects: Vehicle -> Trip ->
# Waybills/Packages -> Orders -> customers, using only existing
# relationships. `revised_arrival` is the disrupted arrival estimate (nil
# when it can't be estimated, e.g. a truck failure with no repair
# estimate) - delay/SLA figures that depend on it are then nil, with
# `unavailable` explaining why, rather than guessed.
class WaybillImpactService
  def initialize(trip, revised_arrival: nil)
    @trip = trip
    @revised_arrival = revised_arrival
  end

  def waybills
    @waybills ||= @trip ? @trip.waybills.open.includes(packages: :order).order(:waybill_number).to_a : []
  end

  def packages
    @packages ||= @trip ? @trip.packages.where.not(status: "delivered").includes(:order).to_a : []
  end

  def orders
    @orders ||= packages.filter_map(&:order).uniq
  end

  def delayed_waybills
    return nil unless @revised_arrival

    waybills.select { |waybill| waybill.expected_arrival_at && @revised_arrival > waybill.expected_arrival_at }
  end

  # Orders whose promised delivery falls before the revised arrival.
  def sla_breach_orders
    return nil unless @revised_arrival

    orders.select { |order| order.promised_delivery_at && order.promised_delivery_at < @revised_arrival }
  end

  def as_json(*)
    {
      waybill_count: waybills.size,
      package_count: packages.size,
      order_count: orders.size,
      customer_count: orders.filter_map(&:customer_reference).uniq.size,
      expected_arrival: waybills.filter_map(&:expected_arrival_at).max&.iso8601 || @trip&.expected_arrival_at&.iso8601,
      revised_arrival: @revised_arrival&.iso8601,
      delayed_waybills: delayed_waybills&.size,
      sla_breach_orders: sla_breach_orders&.size,
      sla_risk: sla_risk,
      waybills: waybills.map { |waybill| waybill_summary(waybill) },
      unavailable: @revised_arrival ? nil : "revised_arrival_unknown"
    }
  end

  # "high" when any order's promised delivery is breached, "medium" when
  # waybills arrive late but no promise is breached, "low" otherwise;
  # nil when the revised arrival isn't known.
  def sla_risk
    return nil unless @revised_arrival
    return "high" if sla_breach_orders.any?
    return "medium" if delayed_waybills.any?

    "low"
  end

  private

  def waybill_summary(waybill)
    refs = waybill.packages.filter_map { |package| package.order&.customer_reference }.uniq
    {
      id: waybill.id,
      waybill_number: waybill.waybill_number,
      status: waybill.status,
      customer: refs.one? ? refs.first : nil,
      customer_count: refs.size,
      package_count: waybill.total_packages,
      order_count: waybill.total_orders,
      weight_kg: waybill.total_weight&.to_f,
      declared_value: waybill.declared_value&.to_f,
      expected_arrival_at: waybill.expected_arrival_at&.iso8601,
      delayed: @revised_arrival && waybill.expected_arrival_at ? @revised_arrival > waybill.expected_arrival_at : nil
    }
  end
end
