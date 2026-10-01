# The one human-readable format for durations stored in minutes (delays,
# ETA variance, time remaining). Under an hour stays in minutes; an hour
# or more is converted to hours with at most one decimal:
#   45 -> "45 min", 60 -> "1 hour", 90 -> "1.5 hours", 149 -> "2.5 hours"
# `signed: true` prefixes "+" for positive values (delays).
module DurationFormat
  module_function

  def minutes(value, signed: false)
    return nil if value.nil?

    total = value.to_f
    sign = total.negative? ? "-" : (signed && total.positive? ? "+" : "")
    magnitude = total.abs
    text = if magnitude < 60
      "#{magnitude.round} min"
    else
      hours = (magnitude / 60.0).round(1)
      hours = hours.to_i if hours == hours.to_i
      "#{hours} #{hours == 1 ? 'hour' : 'hours'}"
    end
    "#{sign}#{text}"
  end

  # Rewrites "+90 min"-style fragments in text written before this format
  # existed (e.g. stored incident summaries) into the same hour format.
  def normalize_text(text)
    text&.gsub(/([+-]?)(\d+) min\b/) { minutes(Regexp.last_match(2).to_i * (Regexp.last_match(1) == "-" ? -1 : 1), signed: Regexp.last_match(1) == "+") }
  end
end
