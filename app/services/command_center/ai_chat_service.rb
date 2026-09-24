module CommandCenter
  # Orchestrates one Command Centre AI chat turn (Phase 5):
  #
  #   user question -> Gemini -> query_command_center function call
  #     -> CommandCenter::QueryService (safe, read-only SQL)
  #     -> compact structured result -> Gemini -> natural-language answer
  #
  # Conversation state lives in AiConversation/AiMessage (app-level, not
  # just the browser) so multi-turn follow-ups ("How many of them...")
  # work across requests. Gemini's `generateContent` is itself stateless -
  # full history is replayed from AiMessage on every turn (see
  # #history_for), as Gemini's native `contents` array of
  # `{role, parts}` entries (NOT a simplified/reinterpreted shape) -
  # gemini-3.8-flash is a "thinking" model whose functionCall parts carry
  # a `thoughtSignature` that must be replayed byte-for-byte or the next
  # turn is rejected (see GeminiClient's header comment) - this is why
  # AiMessage#steps stores raw Gemini `contents` entries, not a
  # hand-rolled trace format.
  class AiChatService
    class ChatError < StandardError; end

    MAX_TOOL_ITERATIONS = 5

    SYSTEM_INSTRUCTIONS = <<~PROMPT.strip
      You are the Command Centre Operations Assistant for Safexpress's
      logistics network. You answer natural-language operational
      questions about hubs, fleet/vehicles, routes/trips, orders,
      packages, delivery, operational alerts, and network snapshots -
      using ONLY the query_command_center tool against the approved
      Command Centre data sources. The database is the source of truth.

      Rules you must always follow:
      - NEVER invent, estimate, guess, or interpolate an operational
        number. Every number in your answer must come from a
        query_command_center tool result.
      - If a value is NULL or a query returns no rows, say so plainly
        (e.g. "Average dwell time is currently unavailable for X because
        there is no completed dwell measurement data.") - do not
        approximate it.
      - If the available data genuinely cannot answer the question, say:
        "I don't currently have enough Command Centre data to answer
        that."
      - Business terminology: "truck"/"fleet vehicle" means a vehicle
        row; "hub"/"gateway"/"hub location" means a hub row;
        "shipment" means a package; "route" means a trip;
        "delayed"/"late" means trip status=delayed or a positive
        eta_variance_minutes; "waiting time"/"dwell time" means
        avg_dwell_time_minutes on vw_hub_dashboard_summary; "vehicle
        currently at a hub" means the vehicle's hub_name/hub_code on
        vw_vehicle_dashboard matches, not its current trip's origin.
      - Prefer the analytical views over raw tables; only use a raw
        table for operational event history, package status history, or
        drill-down detail a view doesn't expose.
      - For explanatory questions ("why is X happening"), only state
        factors the data actually supports (e.g. backlog, parking
        utilisation, turnaround) and explicitly say when the data can't
        explain a contributing factor (e.g. dock utilisation) rather
        than speculating.
      - You are a READ-ONLY analytics assistant. If asked about weather,
        news, general internet information, employee personal
        information, database administration, Slack configuration,
        alert-rule modification, sending notifications, or modifying any
        operational record, do not call any tool - explain that you're
        focused on read-only Command Centre operational analytics.
      - Keep answers concise and operational. Do not mention SQL, table
        names, or internal query structure unless the user explicitly
        asks how you got an answer.
    PROMPT

    def self.call(...)
      new(...).call
    end

    def initialize(message:, session_key: nil)
      @message = message.to_s
      @conversation = AiConversation.find_or_create_by_session_key!(session_key)
    end

    def call
      raise ChatError, "message is required" if @message.blank?

      unless GeminiClient.configured?
        return respond(answer: "The Command Centre AI assistant is not configured yet (GEMINI_API_KEY is unset).", sources: [])
      end

      user_message = AiMessage.create!(ai_conversation: @conversation, role: "user", content: @message)
      history = history_for(@conversation)

      client = GeminiClient.new
      sources_used = []
      turn_contents = []

      MAX_TOOL_ITERATIONS.times do
        response = client.generate(
          contents: history + turn_contents,
          tools: [ GeminiTools.query_command_center_declaration ],
          system_instruction: SYSTEM_INSTRUCTIONS
        )
        parts = extract_parts(response)
        function_call_parts = parts.select { |p| p["functionCall"] }

        if function_call_parts.empty?
          answer = extract_text(parts).presence || "I don't currently have enough Command Centre data to answer that."
          turn_contents << { role: "model", parts: parts }
          persist_assistant_turn(answer: answer, contents: turn_contents)
          return respond(answer: answer, sources: sources_used.uniq)
        end

        turn_contents << { role: "model", parts: parts }

        function_response_parts = function_call_parts.map do |fc_part|
          fn_call = fc_part["functionCall"]
          result = run_tool(fn_call, user_message)
          sources_used << result[:source] if result[:source]
          { functionResponse: { name: fn_call["name"], response: result[:error] ? { error: result[:error] } : result[:payload] } }
        end
        turn_contents << { role: "user", parts: function_response_parts }
      end

      answer = "I wasn't able to finish answering that within the allowed number of steps. Please try a narrower question."
      persist_assistant_turn(answer: answer, contents: turn_contents)
      respond(answer: answer, sources: sources_used.uniq)
    rescue GeminiClient::ApiError => e
      Rails.logger.error("[AiChatService] Gemini API error: #{e.message}")
      respond(answer: "The Command Centre AI assistant couldn't reach Gemini right now. Please try again shortly.", sources: [])
    end

    private

    def respond(answer:, sources:)
      @conversation.touch_last_message!
      { answer: answer, conversation_id: @conversation.session_key, sources: sources }
    end

    def history_for(conversation)
      conversation.ai_messages.flat_map do |m|
        if m.role == "user"
          [ { role: "user", parts: [ { text: m.content } ] } ]
        else
          # `steps` holds the raw {role, parts} entries Gemini itself
          # produced/consumed for this turn (see #call) - replayed
          # verbatim so any thoughtSignature on a functionCall part
          # survives, and so the model sees both its own tool-call trace
          # and its final phrasing (needed for follow-ups like "them").
          Array(m.steps)
        end
      end
    end

    def extract_parts(response)
      response.dig("candidates", 0, "content", "parts") || []
    end

    def extract_text(parts)
      parts.filter_map { |p| p["text"] }.join("\n")
    end

    def run_tool(fn_call, user_message)
      return { error: "Unknown tool: #{fn_call['name']}" } unless fn_call["name"] == GeminiTools::QUERY_COMMAND_CENTER

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      request = GeminiTools.build_query_request(fn_call["args"] || {})

      begin
        result = QueryService.call(request)
        log_query(user_message: user_message, request: request, result: result, started_at: started_at, success: true)
        { source: result.source, payload: result.to_h }
      rescue QueryService::ValidationError => e
        log_query(user_message: user_message, request: request, result: nil, started_at: started_at, success: false, error: e.message)
        { source: request[:source], error: e.message }
      end
    end

    def log_query(user_message:, request:, result:, started_at:, success:, error: nil)
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2)
      AiQueryLog.create!(
        ai_conversation: @conversation,
        session_key: @conversation.session_key,
        question: user_message.content,
        source: request[:source],
        structured_query: request,
        model: ENV.fetch("GEMINI_MODEL", GeminiClient::DEFAULT_MODEL),
        success: success,
        error_message: error,
        row_count: result&.row_count,
        execution_time_ms: elapsed_ms
      )
    rescue StandardError => e
      # Logging must never break the chat itself.
      Rails.logger.error("[AiChatService] failed to write AiQueryLog: #{e.class}: #{e.message}")
    end

    def persist_assistant_turn(answer:, contents:)
      AiMessage.create!(ai_conversation: @conversation, role: "assistant", content: answer, steps: contents.presence)
    end
  end
end
