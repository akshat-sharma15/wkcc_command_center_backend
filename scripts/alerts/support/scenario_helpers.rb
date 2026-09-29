# Shared helpers for the advanced-incident scenario scripts (07-10).
# Requests go through the real Rails stack (routing, controllers,
# serializers) via an in-process integration session - no running server
# needed, and the developer's own dev server is never touched.
require "action_dispatch/testing/integration"

module ScenarioHelpers
  USER_ID = (SupersetDirectory.users.find { |u| u[:username] == "admin" } || SupersetDirectory.users.first || { id: 1 })[:id]

  def self.session
    @session ||= ActionDispatch::Integration::Session.new(Rails.application).tap { |s| s.host! "localhost" }
  end

  def api(verb, path, params = nil)
    headers = { "X-Superset-User-Id" => USER_ID.to_s, "Content-Type" => "application/json", "Accept" => "application/json" }
    # Each request runs on its own thread: the app's executor would
    # otherwise reset the runner thread's execution context (Rails 8.1),
    # breaking every ActiveRecord query this script makes afterwards.
    response = Thread.new do
      ScenarioHelpers.session.public_send(verb, path, params: params&.to_json, headers: headers)
      ScenarioHelpers.session.response
    end.value
    body = response.body.present? ? JSON.parse(response.body) : nil
    [ response.status, body ]
  end

  def check(label, ok, detail = nil)
    $scenario_failures ||= 0
    $scenario_failures += 1 unless ok
    puts "  #{ok ? '✓' : '✗'} #{label}#{detail ? " - #{detail}" : ''}"
    ok
  end

  def section(title)
    puts "\n[#{title}]"
  end

  def show(label, value)
    puts "    #{label.to_s.ljust(22)} #{value.nil? ? '— (unavailable)' : value}"
  end

  # Waits for NotificationDeliveryJob (Sidekiq) to finish each notification.
  def wait_for_delivery(alert_id, timeout: 30)
    deadline = Time.current + timeout
    loop do
      notifications = Notification.where(alert_id: alert_id).to_a
      return notifications if notifications.any? && notifications.none? { |n| n.status == "pending" }
      return notifications if Time.current > deadline

      sleep 1
    end
  end

  def report_delivery(alert_id)
    notifications = wait_for_delivery(alert_id)
    check("notifications created", notifications.any?, "#{notifications.size} (#{notifications.map(&:channel).tally})")
    %w[in_app slack].each do |channel|
      rows = notifications.select { |n| n.channel == channel }
      next check("#{channel} notification", false, "none created") if rows.empty?

      rows.each do |n|
        check("#{channel} delivery (notification ##{n.id})", n.status == "delivered", "#{n.status}#{n.error_message ? ": #{n.error_message}" : ''}")
      end
    end
    notifications
  end

  def finish!
    failures = $scenario_failures.to_i
    puts "\n#{failures.zero? ? '✓ PASSED' : "✗ #{failures} check(s) failed"}"
    # exit! - a plain `exit` inside `rails runner`'s executor trips an
    # ActiveSupport error-reporter bug (SystemExit reported as an error).
    $stdout.flush
    exit!(failures.zero? ? 0 : 1)
  end

  def inr(amount)
    amount.nil? ? nil : "₹#{amount.to_i.to_s.reverse.scan(/\d{1,3}/).join(',').reverse}"
  end
end
