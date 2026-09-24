module CommandCenter
  # Builds and executes exactly ONE parameterized, read-only SELECT
  # against an approved Command Centre source (Phase 5's
  # `query_command_center` Gemini tool lands here). This is the ONLY
  # place SQL is constructed for the AI chatbot - the model never sends
  # SQL, only structured parameters (source/select/filters/group_by/
  # order_by/limit), and every part of that structure is validated
  # against CommandCenter::SourceCatalog before it touches a query
  # string. Values are always bound, never interpolated.
  #
  # Executes via AiReadOnlyRecord (the wkcc_ai_readonly Postgres role -
  # SELECT-only, on approved objects only, read-only at the transaction
  # level too - see AiReadOnlyRecord and docs/ai_readonly_role.sql), so
  # even a bug here still can't write or reach unauthorized data.
  class QueryService
    class ValidationError < StandardError; end

    DEFAULT_LIMIT = 100
    MAX_LIMIT = 500
    STATEMENT_TIMEOUT_MS = 5_000

    AGGREGATIONS = %w[count count_distinct sum avg min max].freeze

    OPERATORS = {
      "equals" => "= ?",
      "not_equals" => "!= ?",
      "contains" => "ILIKE ?",
      "starts_with" => "ILIKE ?",
      "greater_than" => "> ?",
      "less_than" => "< ?",
      "greater_or_equal" => ">= ?",
      "less_or_equal" => "<= ?",
      "in" => "IN (?)",
      "between" => "BETWEEN ? AND ?",
      "is_null" => "IS NULL",
      "is_not_null" => "IS NOT NULL"
    }.freeze

    Result = Struct.new(:source, :row_count, :columns, :rows, keyword_init: true) do
      def to_h
        { source: source, row_count: row_count, columns: columns, rows: rows }
      end
    end

    # request: a Hash (symbol or string keys) shaped like the
    # query_command_center tool's input schema - see
    # CommandCenter::GeminiTools.query_command_center_declaration.
    def self.call(request)
      new(request).call
    end

    def initialize(request)
      @request = request.deep_symbolize_keys
    end

    def call
      source = validate_source!
      select = validate_select!(source)
      operation = validate_operation!
      filters = validate_filters!(source)
      group_by = validate_group_by!(source, select)
      order_by = validate_order_by!(source, select, group_by)
      limit = validate_limit!

      sql, binds = build_sql(source: source, select: select, operation: operation,
                              filters: filters, group_by: group_by, order_by: order_by, limit: limit)

      rows = execute(sql, binds)
      columns = rows.columns
      Result.new(source: source.name, row_count: rows.count, columns: columns, rows: rows.to_a)
    end

    private

    attr_reader :request

    def validate_source!
      name = request[:source].to_s
      source = SourceCatalog.fetch(name)
      raise ValidationError, "Unknown or unauthorized source: #{name.inspect}. Approved sources: #{SourceCatalog.approved_source_names.join(', ')}" unless source

      source
    end

    def validate_operation!
      op = (request[:operation] || "select").to_s
      return "select" if op == "select"

      raise ValidationError, "Unknown aggregation: #{op.inspect}. Allowed: #{AGGREGATIONS.join(', ')}" unless AGGREGATIONS.include?(op)

      op
    end

    def validate_select!(source)
      cols = Array(request[:select]).map(&:to_s)
      return source.column_names if cols.empty?

      unknown = cols - source.column_names
      raise ValidationError, "Unknown column(s) on #{source.name}: #{unknown.join(', ')}" if unknown.any?

      cols
    end

    def validate_filters!(source)
      Array(request[:filters]).map do |f|
        f = f.deep_symbolize_keys
        column = f[:column].to_s
        operator = f[:operator].to_s

        raise ValidationError, "Unknown filter column on #{source.name}: #{column.inspect}" unless source.column_names.include?(column)
        raise ValidationError, "Unknown operator: #{operator.inspect}. Allowed: #{OPERATORS.keys.join(', ')}" unless OPERATORS.key?(operator)

        { column: column, operator: operator, value: f[:value] }
      end
    end

    def validate_group_by!(source, select)
      cols = Array(request[:group_by]).map(&:to_s)
      unknown = cols - source.column_names
      raise ValidationError, "Unknown group_by column(s) on #{source.name}: #{unknown.join(', ')}" if unknown.any?

      cols
    end

    def validate_order_by!(source, select, group_by)
      Array(request[:order_by]).map do |o|
        o = o.deep_symbolize_keys
        column = o[:column].to_s
        direction = (o[:direction] || "asc").to_s.downcase

        raise ValidationError, "Unknown order_by column on #{source.name}: #{column.inspect}" unless source.column_names.include?(column)
        raise ValidationError, "Unknown order_by direction: #{direction.inspect}" unless %w[asc desc].include?(direction)

        { column: column, direction: direction }
      end
    end

    def validate_limit!
      requested = request[:limit].presence || DEFAULT_LIMIT
      limit = Integer(requested)
      raise ValidationError, "limit must be positive" if limit <= 0

      [ limit, MAX_LIMIT ].min
    rescue ArgumentError, TypeError
      raise ValidationError, "Invalid limit: #{request[:limit].inspect}"
    end

    def build_sql(source:, select:, operation:, filters:, group_by:, order_by:, limit:)
      binds = []
      quoted_table = AiReadOnlyRecord.connection.quote_table_name(source.name)

      select_sql =
        if operation == "select"
          select.map { |c| AiReadOnlyRecord.connection.quote_column_name(c) }.join(", ")
        else
          aggregate_select_sql(operation, select, group_by)
        end

      sql = +"SELECT #{select_sql} FROM #{quoted_table}"

      if filters.any?
        clauses = filters.map { |f| filter_clause(f, binds) }
        sql << " WHERE #{clauses.join(' AND ')}"
        sql = number_placeholders(sql)
      end

      if group_by.any?
        sql << " GROUP BY #{group_by.map { |c| AiReadOnlyRecord.connection.quote_column_name(c) }.join(', ')}"
      end

      if order_by.any?
        order_sql = order_by.map { |o| "#{AiReadOnlyRecord.connection.quote_column_name(o[:column])} #{o[:direction].upcase}" }
        sql << " ORDER BY #{order_sql.join(', ')}"
      end

      sql << " LIMIT #{limit.to_i}"

      [ sql, binds ]
    end

    def aggregate_select_sql(operation, select, group_by)
      group_cols = group_by.map { |c| AiReadOnlyRecord.connection.quote_column_name(c) }
      agg_col =
        case operation
        when "count" then "*"
        else
          target = select.first || raise(ValidationError, "#{operation} requires a column in `select`")
          AiReadOnlyRecord.connection.quote_column_name(target)
        end

      agg_sql =
        case operation
        when "count" then "COUNT(#{agg_col})"
        when "count_distinct" then "COUNT(DISTINCT #{agg_col})"
        when "sum" then "SUM(#{agg_col})"
        when "avg" then "AVG(#{agg_col})"
        when "min" then "MIN(#{agg_col})"
        when "max" then "MAX(#{agg_col})"
        end

      (group_cols + [ "#{agg_sql} AS #{operation}" ]).join(", ")
    end

    def filter_clause(filter, binds)
      column_sql = AiReadOnlyRecord.connection.quote_column_name(filter[:column])
      operator_template = OPERATORS.fetch(filter[:operator])

      case filter[:operator]
      when "is_null", "is_not_null"
        "#{column_sql} #{operator_template}"
      when "contains"
        binds << "%#{filter[:value]}%"
        "#{column_sql} #{operator_template}"
      when "starts_with"
        binds << "#{filter[:value]}%"
        "#{column_sql} #{operator_template}"
      when "in"
        values = Array(filter[:value])
        raise ValidationError, "'in' filter requires a non-empty array value" if values.empty?

        placeholders = values.map { |v| binds << v; "?" }.join(", ")
        "#{column_sql} IN (#{placeholders})"
      when "between"
        values = Array(filter[:value])
        raise ValidationError, "'between' filter requires exactly 2 values" unless values.size == 2

        binds.concat(values)
        "#{column_sql} BETWEEN ? AND ?"
      else
        binds << filter[:value]
        "#{column_sql} #{operator_template}"
      end
    end

    # Converts the `?` placeholders used while building the WHERE clause
    # into genuine positional Postgres parameters ($1, $2, ...), matched
    # 1:1 with `binds`. This - not string interpolation, not manual
    # `connection.quote` escaping - is what actually goes to Postgres as
    # a parameterized query.
    def number_placeholders(sql)
      n = 0
      sql.gsub("?") { n += 1; "$#{n}" }
    end

    def bind_attributes(binds)
      binds.map { |v| ActiveRecord::Relation::QueryAttribute.new(nil, v, ActiveRecord::Type::Value.new) }
    end

    def execute(sql, binds)
      AiReadOnlyRecord.connection.transaction do
        AiReadOnlyRecord.connection.execute("SET LOCAL statement_timeout = #{STATEMENT_TIMEOUT_MS}")
        AiReadOnlyRecord.connection.exec_query(sql, "CommandCenter::QueryService", bind_attributes(binds))
      end
    end
  end
end
