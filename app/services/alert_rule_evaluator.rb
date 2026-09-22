# Evaluates whether a single business record currently satisfies an
# AlertRule's condition. Reuses AlertRule.column_type_category (the same
# method the model uses to validate which operators are legal for a
# field) so there is exactly one source of truth for "what type is this
# field" — this class only adds the actual comparison logic, which
# necessarily can't live in AlertRule itself (that's the validation
# layer, not the evaluation layer).
class AlertRuleEvaluator
  def initialize(alert_rule, record)
    @alert_rule = alert_rule
    @record = record
  end

  def matches?
    case AlertRule.column_type_category(@alert_rule.target_model, @alert_rule.field)
    when :numeric then compare_numeric
    when :boolean then compare_boolean
    else compare_default
    end
  end

  # The record's current value for the rule's field, as a plain string —
  # what gets stored on Alert#actual_value.
  def actual_value
    @record.public_send(@alert_rule.field).to_s
  end

  private

  def compare_numeric
    actual = numeric(@record.public_send(@alert_rule.field))
    expected = numeric(@alert_rule.value)
    return false if actual.nil? || expected.nil?

    case @alert_rule.operator
    when "=" then actual == expected
    when "!=" then actual != expected
    when ">" then actual > expected
    when "<" then actual < expected
    when ">=" then actual >= expected
    when "<=" then actual <= expected
    else false
    end
  end

  def numeric(value)
    Float(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def compare_boolean
    actual = ActiveModel::Type::Boolean.new.cast(@record.public_send(@alert_rule.field))
    expected = ActiveModel::Type::Boolean.new.cast(@alert_rule.value)

    case @alert_rule.operator
    when "=" then actual == expected
    when "!=" then actual != expected
    else false
    end
  end

  def compare_default
    actual = @record.public_send(@alert_rule.field).to_s
    expected = @alert_rule.value.to_s

    case @alert_rule.operator
    when "=" then actual == expected
    when "!=" then actual != expected
    when "contains" then actual.include?(expected)
    else false
    end
  end
end
