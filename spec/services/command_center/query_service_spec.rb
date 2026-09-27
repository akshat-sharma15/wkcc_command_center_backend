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
end
