module CommandCenter
  # Confines one AI chat conversation to a single Superset chart and the
  # dataset behind it.
  #
  # Superset builds the context (it owns the chart/dataset permission model
  # and resolves a chart id server-side - see superset/chart_chat/api.py in
  # the Superset repo); this class turns that context into the two things the
  # chat turn actually needs: the prompt text describing the chart, and the
  # single source name the query tool is allowed to touch. The allow-list is
  # what keeps a chart chat from wandering into the rest of the Command
  # Centre schema even if the model asks it to - see
  # AiChatService#source_allowed?.
  class ChartScope
    attr_reader :chart, :dataset

    def initialize(context)
      context = (context || {}).with_indifferent_access
      @chart = context[:chart] || {}
      @dataset = context[:dataset]
    end

    def chart_id
      chart[:id]
    end

    def chart_name
      chart[:name].presence || "this chart"
    end

    # Binds a conversation to this chart so a conversation_id issued for one
    # chart (or for the unscoped global chat) can't be replayed against
    # another - see AiConversation.find_or_create_for_scope!.
    def scope_key
      "chart:#{chart_id}"
    end

    def dataset_name
      dataset && dataset[:name].presence
    end

    # The one source this conversation may query, or nil when the chart's
    # dataset isn't an approved Command Centre source - in which case the
    # assistant is limited to describing the chart's own configuration
    # rather than querying anything.
    def allowed_source
      return @allowed_source if defined?(@allowed_source)

      @allowed_source = dataset_name && SourceCatalog.fetch(dataset_name) ? dataset_name : nil
    end

    def queryable?
      allowed_source.present?
    end

    # Sent when the chat opens, so the user gets a summary without having to
    # ask for one.
    def summary_prompt
      if queryable?
        <<~PROMPT.strip
          Summarise the chart "#{chart_name}" for me. Query #{allowed_source}
          for the figures this chart is built on, then give me a few bullet
          points: the headline number(s) this chart reports, the most
          notable breakdown or outlier in the data, and one observation an
          operations user would care about. Finish by telling me I can ask
          follow-up questions about this chart or its dataset.
        PROMPT
      else
        <<~PROMPT.strip
          Describe the chart "#{chart_name}" using only the chart
          configuration in your instructions. Explain what it measures and
          how it is sliced, then state plainly that its dataset is not one
          of the approved Command Centre sources, so you cannot report
          figures from it. Do not state any numbers.
        PROMPT
      end
    end

    def system_instruction_addendum
      <<~PROMPT.strip
        CHART-SCOPED CONVERSATION
        ==========================
        This conversation is about ONE Superset chart. Every answer,
        including follow-ups, must stay within this chart and its dataset.

        #{chart_description}

        #{dataset_description}

        Additional rules for this conversation, which override any general
        guidance above where they conflict:
        - #{source_rule}
        - Interpret every follow-up ("why is that high?", "show the
          breakdown", "which region leads?") as being about this chart's
          dataset. Never answer from another dataset, chart, or dashboard.
        - If the user asks about something this dataset cannot answer, say
          that it is outside what this chart's dataset covers, and tell them
          to use the main Command Centre assistant for network-wide
          questions.
        - Never invent a number. Every figure must come from a tool result.
      PROMPT
    end

    private

    def chart_description
      lines = [ "CHART", "- Name: #{chart_name}" ]
      lines << "- Visualisation type: #{chart[:viz_type]}" if chart[:viz_type].present?
      lines << "- Description: #{chart[:description]}" if chart[:description].present?
      dashboards = Array(chart[:dashboards]).compact_blank
      lines << "- Appears on dashboard(s): #{dashboards.join(', ')}" if dashboards.any?
      lines.concat(query_lines)
      lines.join("\n")
    end

    def query_lines
      query = (chart[:query] || {}).compact_blank
      return [] if query.blank?

      lines = [ "- How this chart is configured:" ]
      lines << "  - Measures: #{format_value(query[:metrics])}" if query[:metrics].present?
      lines << "  - Grouped by: #{format_value(query[:dimensions])}" if query[:dimensions].present?
      lines << "  - Chart filters: #{format_value(query[:filters])}" if query[:filters].present?
      lines << "  - Time range: #{query[:time_range]}" if query[:time_range].present?
      lines << "  - Time grain: #{query[:time_grain]}" if query[:time_grain].present?
      lines << "  - Row limit: #{query[:row_limit]}" if query[:row_limit].present?
      lines
    end

    def dataset_description
      return "DATASET\n- This chart's dataset is no longer available." if dataset.blank?

      lines = [ "DATASET", "- Name: #{dataset_name}" ]
      lines << "- Database: #{dataset[:database_name]}" if dataset[:database_name].present?
      columns = Array(dataset[:columns])
      if columns.any?
        lines << "- Columns:"
        columns.each do |column|
          detail = [ column[:type], column[:description].presence ].compact_blank.join(" - ")
          lines << "  - #{column[:name]}#{" (#{detail})" if detail.present?}"
        end
      end
      metrics = Array(dataset[:metrics])
      if metrics.any?
        lines << "- Dataset metrics:"
        metrics.each do |metric|
          label = metric[:verbose_name].presence || metric[:name]
          lines << "  - #{metric[:name]}#{" (#{label})" unless label == metric[:name]}"
        end
      end
      lines.join("\n")
    end

    def source_rule
      if queryable?
        "You may ONLY call query_command_center with source=\"#{allowed_source}\". " \
        "Requests for any other source will be rejected."
      else
        "This chart's dataset is not an approved Command Centre source, so do " \
        "NOT call query_command_center at all. Answer only from the chart " \
        "configuration above, and state that you cannot report figures for it."
      end
    end

    def format_value(value)
      case value
      when Array then value.map { |entry| format_value(entry) }.join("; ")
      when Hash
        # Superset adhoc filters/metrics arrive as nested config hashes; keep
        # the human-meaningful fields rather than dumping raw JSON.
        value.values_at(:subject, :operator, :comparator, :sqlExpression, :label, :expressionType)
             .compact_blank.join(" ")
             .presence || value.to_json
      else value.to_s
      end
    end
  end
end
