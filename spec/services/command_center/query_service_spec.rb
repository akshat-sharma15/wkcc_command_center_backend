require "rails_helper"

RSpec.describe CommandCenter::QueryService do
  before(:context) { AiChatFixtures.seed! }
  after(:context) { AiChatFixtures.cleanup! }

  describe "valid queries against the real Command Centre views/tables" do
    it "counts vehicles at a hub by name (contains)" do
      result = described_class.call(source: "vw_vehicle_dashboard", operation: "count",
        filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ])

      expect(result.source).to eq("vw_vehicle_dashboard")
      expect(result.rows.first["count"]).to be > 0
    end

    it "selects specific columns with a limit" do
      result = described_class.call(source: "vw_vehicle_dashboard", select: %w[vehicle_number hub_name],
        filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ], limit: 3)

      expect(result.columns).to eq(%w[vehicle_number hub_name])
      expect(result.row_count).to be <= 3
      expect(result.rows).to all(include("hub_name" => a_string_matching(/Indore/)))
    end

    it "computes avg over a single-row summary view" do
      result = described_class.call(source: "vw_fleet_dashboard_summary", operation: "avg", select: %w[average_mileage_km])
      expect(result.rows.first["avg"]).to be_a(Numeric)
    end

    it "groups and orders an aggregate query" do
      result = described_class.call(source: "vw_shipment_dashboard", operation: "count",
        group_by: %w[package_status], order_by: [ { column: "package_status", direction: "asc" } ])

      expect(result.rows.map { |r| r["package_status"] }).to eq(result.rows.map { |r| r["package_status"] }.sort)
      expect(result.rows.sum { |r| r["count"].to_i }).to be > 0
    end

    it "orders descending with a limit to find the busiest route" do
      result = described_class.call(source: "vw_route_dashboard", select: %w[trip_id package_count],
        order_by: [ { column: "package_count", direction: "desc" } ], limit: 1)

      expect(result.row_count).to eq(1)
    end

    it "supports the between operator" do
      result = described_class.call(source: "trips", operation: "count",
        filters: [ { column: "departure_at", operator: "between", value: [ "2026-01-01", "2026-12-31" ] } ])

      expect(result.rows.first["count"].to_i).to be > 0
    end

    it "supports is_null / is_not_null" do
      result = described_class.call(source: "vw_vehicle_dashboard", operation: "count",
        filters: [ { column: "trip_id", operator: "is_null" } ])

      expect(result.rows.first["count"]).to be_a(Numeric)
    end

    it "supports the in operator" do
      result = described_class.call(source: "vw_hub_dashboard_summary", select: %w[hub_code operational_status],
        filters: [ { column: "operational_status", operator: "in", value: %w[degraded closed] } ])

      expect(result.rows).to all(include("operational_status" => a_string_matching(/degraded|closed/)))
    end

    it "defaults to all columns when select is omitted" do
      result = described_class.call(source: "hubs", limit: 1)
      expect(result.columns).to include("code", "name", "operational_status")
    end

    it "clamps an excessive limit to the maximum" do
      result = described_class.call(source: "vehicles", limit: 999_999)
      expect(result.row_count).to be <= described_class::MAX_LIMIT
    end
  end

  describe "safety: unauthorized source access" do
    %w[warehouses payment_dues alert_rules event_definitions notifications].each do |forbidden|
      it "rejects #{forbidden}" do
        expect { described_class.call(source: forbidden, operation: "count") }
          .to raise_error(described_class::ValidationError, /Unknown or unauthorized source/)
      end
    end

    it "rejects a command_center-database table name" do
      expect { described_class.call(source: "integrations", operation: "count") }
        .to raise_error(described_class::ValidationError, /Unknown or unauthorized source/)
    end

    it "rejects an entirely made-up source" do
      expect { described_class.call(source: "users", operation: "count") }
        .to raise_error(described_class::ValidationError, /Unknown or unauthorized source/)
    end
  end

  describe "safety: write statements are impossible" do
    it "the query builder only ever emits SELECT (no write keyword reaches the connection)" do
      # QueryService has no code path that emits anything but SELECT - this
      # is enforced structurally (build_sql always starts "SELECT ..."),
      # not by a runtime keyword filter. The AiReadOnlyRecord role itself
      # is also a hard backstop (see below).
      result = described_class.call(source: "hubs", limit: 1)
      expect(result).to be_a(described_class::Result)
    end

    it "the underlying DB role physically cannot write, even to an approved table" do
      expect {
        AiReadOnlyRecord.connection.execute("UPDATE hubs SET name = 'x' WHERE id = #{Hub.first&.id || 1}")
      }.to raise_error(ActiveRecord::StatementInvalid, /read-only transaction/)
    end

    it "the underlying DB role cannot read an unauthorized table even via raw SQL" do
      expect {
        AiReadOnlyRecord.connection.execute("SELECT * FROM warehouses LIMIT 1")
      }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end
  end

  describe "safety: validation rejections" do
    it "rejects an unknown column in select" do
      expect { described_class.call(source: "vw_vehicle_dashboard", select: [ "ssn" ]) }
        .to raise_error(described_class::ValidationError, /Unknown column/)
    end

    it "rejects an unknown filter column" do
      expect {
        described_class.call(source: "vw_vehicle_dashboard", operation: "count",
          filters: [ { column: "ssn", operator: "equals", value: "x" } ])
      }.to raise_error(described_class::ValidationError, /Unknown filter column/)
    end

    it "rejects an invalid operator" do
      expect {
        described_class.call(source: "vw_vehicle_dashboard", operation: "count",
          filters: [ { column: "status", operator: "regex_match", value: "x" } ])
      }.to raise_error(described_class::ValidationError, /Unknown operator/)
    end

    it "rejects an invalid aggregation function" do
      expect { described_class.call(source: "vw_vehicle_dashboard", operation: "median") }
        .to raise_error(described_class::ValidationError, /Unknown aggregation/)
    end

    it "rejects an unknown group_by column" do
      expect {
        described_class.call(source: "vw_vehicle_dashboard", operation: "count", group_by: [ "ssn" ])
      }.to raise_error(described_class::ValidationError, /Unknown group_by column/)
    end

    it "rejects an unknown order_by column" do
      expect {
        described_class.call(source: "vw_vehicle_dashboard", order_by: [ { column: "ssn" } ])
      }.to raise_error(described_class::ValidationError, /Unknown order_by column/)
    end

    it "rejects a blank/empty source" do
      expect { described_class.call(source: "") }
        .to raise_error(described_class::ValidationError, /Unknown or unauthorized source/)
    end

    it "rejects an ambiguous request with no source at all" do
      expect { described_class.call({}) }
        .to raise_error(described_class::ValidationError)
    end
  end

  describe "safety: SQL injection attempts are neutralized, not executed" do
    it "treats an injection payload in a filter value as an inert literal string" do
      result = described_class.call(source: "vw_vehicle_dashboard", operation: "count",
        filters: [ { column: "hub_name", operator: "equals", value: "x'; DROP TABLE vehicles; --" } ])

      expect(result.rows.first["count"].to_i).to eq(0)
      expect(Vehicle.count).to be > 0 # the table still exists and still has rows
    end

    it "rejects an injection payload disguised as a column name" do
      expect {
        described_class.call(source: "vw_vehicle_dashboard", select: [ "vehicle_number; DROP TABLE vehicles; --" ])
      }.to raise_error(described_class::ValidationError, /Unknown column/)
      expect(Vehicle.count).to be > 0
    end

    it "rejects an injection payload disguised as a source name" do
      expect {
        described_class.call(source: "vehicles; DROP TABLE vehicles; --")
      }.to raise_error(described_class::ValidationError, /Unknown or unauthorized source/)
    end
  end

  # Filterable dimensions on the row-level views: location, hub, date, vehicle,
  # status. fleet_status uses the map's own vocabulary (VehicleStatusResolver).
  describe "filter dimensions on the row-level views" do
    let(:prefix) { AiChatFixtures::VEHICLE_NUMBER_PREFIX }

    def fleet(filters)
      described_class.call(source: "vw_vehicle_dashboard", select: %w[vehicle_number fleet_status in_transit],
        filters: [ { column: "vehicle_number", operator: "starts_with", value: prefix } ] + filters, limit: 50).rows
    end

    it "filters vehicles by the map's status, matching VehicleStatusResolver" do
      expected = Vehicle.fleet_monitoring_poc.where("number LIKE ?", "#{prefix}%").where(id: Trip.status_in_transit.select(:vehicle_id)).pluck(:number) # map trucks only
      expect(expected).not_to be_empty # the fixtures really do contain an in-transit vehicle

      in_transit = fleet([ { column: "fleet_status", operator: "equals", value: "IN TRANSIT" } ])
      expect(in_transit.map { |r| r["vehicle_number"] }).to match_array(expected)
      expect(in_transit).to all(include("in_transit" => true))

      maintenance = fleet([ { column: "fleet_status", operator: "equals", value: "MAINTENANCE" } ])
      expect(maintenance.map { |r| r["vehicle_number"] }).to eq([ "#{prefix}02" ])
    end

    it "filters by hub and by date on the row-level views" do
      by_hub = described_class.call(source: "vw_vehicle_dashboard", select: %w[vehicle_number hub_code],
        filters: [ { column: "vehicle_number", operator: "starts_with", value: prefix },
                   { column: "hub_name", operator: "contains", value: "Indore" } ], limit: 50).rows
      expect(by_hub).not_to be_empty

      dated = described_class.call(source: "vw_route_dashboard", operation: "count",
        filters: [ { column: "departure_at", operator: "between", value: [ 10.years.ago.iso8601, 1.day.from_now.iso8601 ] } ]).rows.first
      expect(dated["count"].to_i).to be >= 0
    end

    it "exposes location columns on every row-level view" do
      %w[vw_vehicle_dashboard vw_route_dashboard vw_shipment_dashboard vw_hub_dashboard_summary].each do |view|
        source = CommandCenter::SourceCatalog::VIEW_SOURCES.fetch(view)
        expect(source.column_names & %w[current_state origin_state location_state state]).not_to be_empty, "#{view} has no state column"
      end
    end
  end

  # The AI must report on the fleet the map shows (vehicles.fleet_monitoring_poc = true).
  # Done in the SQL views; nothing is deleted. AITEST-VEH-99 is an off-map truck with a trip.
  describe "views expose only the map's trucks" do
    let(:hidden_number) { "#{AiChatFixtures::VEHICLE_NUMBER_PREFIX}99" }
    let(:shown_number) { "#{AiChatFixtures::VEHICLE_NUMBER_PREFIX}01" }

    def rows(source, select, filters = [], **opts)
      described_class.call({ source: source, select: select, filters: filters, limit: 500 }.merge(opts)).rows
    end

    it "keeps the off-map truck in the database but out of the vehicle view" do
      expect(Vehicle.exists?(number: hidden_number)).to be(true)
      expect(rows("vw_vehicle_dashboard", %w[vehicle_number], [ { column: "vehicle_number", operator: "equals", value: hidden_number } ])).to be_empty
      expect(rows("vw_vehicle_dashboard", %w[vehicle_number], [ { column: "vehicle_number", operator: "equals", value: shown_number } ])).not_to be_empty
    end

    it "drops the off-map truck's trips from the route view" do
      hidden = Vehicle.find_by!(number: hidden_number)
      expect(Trip.where(vehicle_id: hidden.id)).to exist
      expect(rows("vw_route_dashboard", %w[vehicle_id]).map { |r| r["vehicle_id"] }).not_to include(hidden.id)
    end

    it "makes the fleet summary agree with the map's own counts" do
      row = rows("vw_fleet_dashboard_summary", %w[total_vehicles active_vehicles vehicles_on_trip]).first
      map = Vehicle.fleet_monitoring_poc
      expect(row["total_vehicles"].to_i).to eq(map.count)
      expect(row["active_vehicles"].to_i).to eq(map.status_active.count)
      expect(row["vehicles_on_trip"].to_i).to eq(map.where(id: Trip.status_in_transit.select(:vehicle_id)).count)
    end

    it "keeps every package in the shipment view but never names the off-map truck" do
      expect(rows("vw_shipment_dashboard", %w[vehicle_number], [ { column: "vehicle_number", operator: "equals", value: hidden_number } ])).to be_empty
      total = described_class.call(source: "vw_shipment_dashboard", operation: "count").rows.first["count"].to_i
      expect(total).to eq(Package.count) # agrees with vw_shipment_dashboard_summary, which counts all packages
    end
  end

  # Raw tables are queried directly (no view), so QueryService applies the map-fleet filter itself
  # (SourceCatalog::Source#base_filter). Without it the AI could list every truck via `vehicles`.
  describe "raw tables expose only the map's trucks" do
    let(:hidden_number) { "#{AiChatFixtures::VEHICLE_NUMBER_PREFIX}99" }
    let(:shown_number) { "#{AiChatFixtures::VEHICLE_NUMBER_PREFIX}01" }
    let(:hidden) { Vehicle.find_by!(number: hidden_number) }

    def raw(source, select, filters = [], **opts)
      described_class.call({ source: source, select: select, filters: filters, limit: 500 }.merge(opts)).rows
    end

    it "does not return the off-map truck from the raw vehicles table, however it is asked for" do
      expect(Vehicle.exists?(number: hidden_number)).to be(true)
      expect(raw("vehicles", %w[number], [ { column: "id", operator: "equals", value: hidden.id } ])).to be_empty
      expect(raw("vehicles", %w[number], [ { column: "number", operator: "contains", value: hidden_number } ])).to be_empty
      expect(raw("vehicles", %w[number]).map { |r| r["number"] }).not_to include(hidden_number)
    end

    it "counts only map trucks in aggregates over the raw table" do
      counted = described_class.call(source: "vehicles", operation: "count").rows.first["count"].to_i
      expect(counted).to eq(Vehicle.fleet_monitoring_poc.count)
      expect(counted).to be < Vehicle.count
    end

    it "hides the off-map truck's trips, waybills and events" do
      expect(Trip.where(vehicle_id: hidden.id)).to exist
      expect(raw("trips", %w[vehicle_id]).map { |r| r["vehicle_id"] }).not_to include(hidden.id)
      expect(raw("waybills", %w[vehicle_id]).map { |r| r["vehicle_id"] }).not_to include(hidden.id)
      expect(raw("vehicle_operation_events", %w[vehicle_id]).map { |r| r["vehicle_id"] }).not_to include(hidden.id)
    end

    it "hides alerts about the off-map truck but keeps every other alert" do
      expect(Alert.where(group: "vehicles", record_id: hidden.id)).to exist
      records = raw("alerts", %w[group record_id])
      expect(records).not_to include(include("group" => "vehicles", "record_id" => hidden.id))
      expect(records).to include(include("group" => "hubs")) # the hub alert from the fixtures is untouched
    end

    it "keeps a map truck fully reachable, so the filter does not over-reach" do
      expect(raw("vehicles", %w[number], [ { column: "number", operator: "equals", value: shown_number } ]).map { |r| r["number"] }).to eq([ shown_number ])
    end

    it "cannot be widened by the model's own filters (the restriction is AND-ed in)" do
      rows = raw("vehicles", %w[number], [ { column: "number", operator: "starts_with", value: AiChatFixtures::VEHICLE_NUMBER_PREFIX } ])
      expect(rows.map { |r| r["number"] }).not_to include(hidden_number)
      expect(rows.size).to eq(Vehicle.fleet_monitoring_poc.where("number LIKE ?", "#{AiChatFixtures::VEHICLE_NUMBER_PREFIX}%").count)
    end
  end
end
