module CommandCenter
  # The single Gemini function declaration the Command Centre AI chatbot
  # exposes. Gemini requests this function with structured arguments;
  # Rails (CommandCenter::QueryService) builds and runs the actual SQL -
  # the model never sends SQL itself.
  module GeminiTools
    QUERY_COMMAND_CENTER = "query_command_center".freeze

    def self.query_command_center_declaration
      {
        name: QUERY_COMMAND_CENTER,
        description: <<~DESC.strip,
          Execute a safe, read-only analytical query against one approved
          Command Centre data source (an analytical view or a raw
          operations table). Prefer the analytical views
          (vw_hub_dashboard_summary, vw_hub_dashboard_overview,
          vw_fleet_dashboard_summary, vw_vehicle_dashboard,
          vw_route_dashboard, vw_shipment_dashboard_summary,
          vw_shipment_dashboard, vw_network_health_summary) - they already
          carry resolved names, joins, and counts. Only use a raw table
          (hubs, vehicles, trips, packages, orders, hub_operations_events,
          vehicle_operation_events, package_status_transitions,
          workforce_members, alerts) for operational event history,
          package status history, or detail a view doesn't expose. Every
          column you reference MUST come from the source's own catalog -
          never guess a column name.
        DESC
        parameters: {
          type: "OBJECT",
          properties: {
            source: {
              type: "STRING",
              description: "The exact name of one approved view or table, e.g. vw_vehicle_dashboard."
            },
            operation: {
              type: "STRING",
              description: "select (default, returns raw rows) or an aggregation: count, count_distinct, sum, avg, min, max.",
              enum: %w[select count count_distinct sum avg min max]
            },
            select: {
              type: "ARRAY",
              items: { type: "STRING" },
              description: "Columns to return (select) or to aggregate (for count_distinct/sum/avg/min/max, the first entry is the aggregated column). Omit for select to return all of the source's columns."
            },
            filters: {
              type: "ARRAY",
              description: "WHERE conditions, ANDed together.",
              items: {
                type: "OBJECT",
                properties: {
                  column: { type: "STRING" },
                  operator: {
                    type: "STRING",
                    enum: %w[equals not_equals contains starts_with greater_than less_than greater_or_equal less_or_equal in between is_null is_not_null]
                  },
                  value: {
                    type: "STRING",
                    description: "The comparison value. For 'in' pass a comma-separated list. For 'between' pass 'low,high'. Omit for is_null/is_not_null."
                  }
                },
                required: %w[column operator]
              }
            },
            group_by: {
              type: "ARRAY",
              items: { type: "STRING" },
              description: "Columns to group by when using an aggregation."
            },
            order_by: {
              type: "ARRAY",
              items: {
                type: "OBJECT",
                properties: {
                  column: { type: "STRING" },
                  direction: { type: "STRING", enum: %w[asc desc] }
                },
                required: [ "column" ]
              }
            },
            limit: {
              type: "INTEGER",
              description: "Max rows to return. Default 100, hard-capped at 500."
            }
          },
          required: [ "source" ]
        }
      }
    end

    def self.declarations
      [ query_command_center_declaration ]
    end

    # Adapts the model's flat function-call arguments (filter.value as a
    # plain string, e.g. for `in`/`between`) into the shape
    # CommandCenter::QueryService expects.
    def self.build_query_request(args)
      args = args.deep_symbolize_keys
      filters = Array(args[:filters]).map do |f|
        f = f.deep_symbolize_keys
        { column: f[:column], operator: f[:operator], value: coerce_filter_value(f[:operator], f[:value]) }
      end

      {
        source: args[:source],
        operation: args[:operation],
        select: args[:select],
        filters: filters,
        group_by: args[:group_by],
        order_by: args[:order_by],
        limit: args[:limit]
      }.compact
    end

    def self.coerce_filter_value(operator, value)
      case operator.to_s
      when "in"
        value.to_s.split(",").map(&:strip)
      when "between"
        value.to_s.split(",").map(&:strip)
      else
        value
      end
    end
  end
end
