# Generates a realistic synthetic Command Centre dataset for Superset/
# dashboard testing (Phase 3). Deliberately separate from `db:seed` - see
# lib/command_centre_demo_seed.rb for the full design notes, safety
# guarantees (never touches alert_rules/alerts/event_definitions/
# notifications/warehouses), and determinism (fixed seed + fixed anchor
# time, safely re-runnable).
namespace :command_centre do
  desc "Seed a deterministic synthetic Command Centre dataset (hubs, vehicles, trips, orders, packages, events) for dashboard testing"
  task seed_demo: :environment do
    require Rails.root.join("lib", "command_centre_demo_seed")
    CommandCentreDemoSeed.run!
  end
end
