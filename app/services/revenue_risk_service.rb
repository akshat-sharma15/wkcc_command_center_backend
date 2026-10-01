# Revenue-risk estimate for disrupted consignments, from stored data only.
#
#   revenue_risk = SUM(waybills.declared_value) over at-risk waybills
#
# where a waybill is "at risk" when its revised arrival is later than its
# expected_arrival_at, or - when no revised arrival can be estimated
# (e.g. a truck failure with no repair estimate) - every open waybill on
# the disrupted trip. declared_value is the goods value stated on the
# waybill; the schema has no order/invoice value, so this is the only
# monetary basis available. If none of the at-risk waybills carries a
# declared value, revenue_risk is nil with `unavailable:
# "no_declared_values"` - never an invented number.
class RevenueRiskService
  CURRENCY = "INR".freeze
  FORMULA = "sum(declared_value) of waybills whose revised arrival exceeds expected_arrival_at " \
            "(all open waybills when no revised arrival is known)".freeze

  def initialize(waybills, revised_arrival:)
    @waybills = waybills
    @revised_arrival = revised_arrival
  end

  def at_risk_waybills
    @at_risk_waybills ||= if @revised_arrival
      @waybills.select { |waybill| waybill.expected_arrival_at && @revised_arrival > waybill.expected_arrival_at }
    else
      @waybills
    end
  end

  def revenue_risk
    valued = at_risk_waybills.reject { |waybill| waybill.declared_value.nil? }
    valued.any? ? valued.sum { |waybill| waybill.declared_value.to_d }.round(2) : nil
  end

  def as_json(*)
    value = revenue_risk
    {
      revenue_risk: value&.to_f,
      currency: CURRENCY,
      formula: FORMULA,
      at_risk_waybills: at_risk_waybills.size,
      unvalued_at_risk_waybills: at_risk_waybills.count { |waybill| waybill.declared_value.nil? },
      unavailable: value.nil? && at_risk_waybills.any? ? "no_declared_values" : nil
    }
  end
end
