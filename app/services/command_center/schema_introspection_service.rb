module CommandCenter
  # Safe, read-only schema introspection for the AI chatbot's approved
  # sources only - never anything else. Reads only
  # information_schema.tables/columns, scoped to exactly the names in
  # SourceCatalog::SOURCES, so it can never leak the shape of
  # warehouses/payment_dues/alert_rules/event_definitions/notifications
  # or any command_center/primary table, let alone credentials.
  #
  # Cached in Rails.cache so we don't hit information_schema on every
  # chat message - see #refresh! to force a re-read (e.g. after adding a
  # new approved source to SourceCatalog).
  module SchemaIntrospectionService
    CACHE_KEY = "command_center/schema_introspection/v1"
    CACHE_TTL = 1.hour

    # { "source_name" => [{ "column_name" => ..., "data_type" => ... }, ...] }
    def self.approved_schema
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { introspect }
    end

    def self.refresh!
      Rails.cache.delete(CACHE_KEY)
      approved_schema
    end

    # Cross-checks the curated SourceCatalog against what the database
    # actually has, for the approved sources only. Returns a list of
    # human-readable discrepancies (empty when everything matches) -
    # intended for a rake task / admin check, not the hot chat path.
    def self.catalog_drift
      live = approved_schema
      drift = []

      SourceCatalog::SOURCES.each_value do |source|
        live_columns = live[source.name]
        if live_columns.nil?
          drift << "#{source.name}: not found in the database (or not an approved source)"
          next
        end

        live_names = live_columns.map { |c| c["column_name"] }.to_set
        catalog_names = source.column_names.to_set

        (catalog_names - live_names).each { |c| drift << "#{source.name}.#{c}: in SourceCatalog but not in the database" }
        (live_names - catalog_names).each { |c| drift << "#{source.name}.#{c}: in the database but not in SourceCatalog" }
      end

      drift
    end

    def self.introspect
      names = SourceCatalog.approved_source_names
      return {} if names.empty?

      sql = ActiveRecord::Base.sanitize_sql_array([
        <<~SQL, names
          SELECT table_name, column_name, data_type, is_nullable
          FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name IN (?)
          ORDER BY table_name, ordinal_position
        SQL
      ])
      result = AiReadOnlyRecord.connection.exec_query(sql, "SchemaIntrospectionService#introspect")

      result.to_a.group_by { |row| row["table_name"] }
    end
    private_class_method :introspect
  end
end
