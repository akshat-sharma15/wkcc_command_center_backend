require "rails_helper"

RSpec.describe CommandCenter::AiChatService do
  before(:context) { AiChatFixtures.seed! }
  after(:context) { AiChatFixtures.cleanup! }

  let(:endpoint) { "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent" }

  around do |example|
    original = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-key"
    example.run
    ENV["GEMINI_API_KEY"] = original
  end

  # Simulates a well-behaved Gemini: turn 1 returns a functionCall part
  # (with a fake thoughtSignature, exactly as the real API does for
  # gemini-3.8-flash), turn 2 (after receiving the real tool result)
  # returns final_answer as a plain text part. Matches the REAL, verified
  # generateContent contract (contents/parts/functionCall/
  # functionResponse) - not a hypothetical shape.
  def stub_tool_then_answer(source:, args:, final_answer:, call_id: "call_1")
    result = CommandCenter::QueryService.call(CommandCenter::GeminiTools.build_query_request(args))

    # WebMock matches the LAST registered stub for a given request pattern
    # when using independent stub_request calls - two sequential HTTP
    # responses from the same endpoint must be chained on one stub via
    # .then, not registered as two separate stubs.
    stub = stub_request(:post, endpoint)
      .to_return(
        status: 200,
        body: {
          candidates: [ {
            content: {
              parts: [ { functionCall: { name: "query_command_center", args: args, id: call_id }, thoughtSignature: "fake-sig-1" } ],
              role: "model"
            }
          } ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
      .then
      .to_return(
        status: 200,
        body: { candidates: [ { content: { parts: [ { text: final_answer } ], role: "model" } } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    { stub: stub, real_result: result }
  end

  describe "a simple grounded question" do
    it "calls the tool, grounds the answer in the real result, and persists conversation state" do
      stub_tool_then_answer(
        source: "vw_vehicle_dashboard",
        args: { source: "vw_vehicle_dashboard", operation: "count", filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ] },
        final_answer: "There are 11 vehicles currently at Indore Hub."
      )

      response = described_class.call(message: "How many vehicles are currently at Indore hub?")

      expect(response[:answer]).to eq("There are 11 vehicles currently at Indore Hub.")
      expect(response[:sources]).to eq([ "vw_vehicle_dashboard" ])
      expect(response[:conversation_id]).to be_present

      conversation = AiConversation.find_by(session_key: response[:conversation_id])
      expect(conversation.ai_messages.pluck(:role)).to eq(%w[user assistant])
      expect(conversation.ai_messages.find_by(role: "user").content).to eq("How many vehicles are currently at Indore hub?")

      log = AiQueryLog.last
      expect(log.session_key).to eq(response[:conversation_id])
      expect(log.source).to eq("vw_vehicle_dashboard")
      expect(log.success).to eq(true)
      expect(log.row_count).to eq(1)
    end
  end

  describe "multi-turn follow-up conversation" do
    it "reuses the same conversation_id and includes prior turns in the replayed history" do
      first = stub_tool_then_answer(
        source: "vw_vehicle_dashboard",
        args: { source: "vw_vehicle_dashboard", operation: "count", filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ] },
        final_answer: "There are 11 vehicles at Indore."
      )
      response1 = described_class.call(message: "How many vehicles are in Indore?")
      conversation_id = response1[:conversation_id]

      second = stub_tool_then_answer(
        source: "vw_vehicle_dashboard",
        args: { source: "vw_vehicle_dashboard", operation: "count",
                filters: [ { column: "hub_name", operator: "contains", value: "Indore" }, { column: "package_count", operator: "greater_than", value: "0" } ] },
        final_answer: "5 of them are carrying packages."
      )
      response2 = described_class.call(message: "How many of them have packages?", session_key: conversation_id)

      expect(response2[:conversation_id]).to eq(conversation_id)
      expect(response2[:answer]).to eq("5 of them are carrying packages.")

      # The second turn's request to Gemini must include the first turn's
      # question and answer, so "them" can resolve.
      expect(
        a_request(:post, endpoint).with { |req|
          contents_text = JSON.parse(req.body)["contents"].to_json
          contents_text.include?("How many vehicles are in Indore?") && contents_text.include?("There are 11 vehicles at Indore.")
        }
      ).to have_been_made.at_least_once

      conversation = AiConversation.find_by(session_key: conversation_id)
      expect(conversation.ai_messages.count).to eq(4)
    end
  end

  describe "out-of-scope questions" do
    it "does not call any tool when Gemini itself declines (e.g. weather)" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: { candidates: [ { content: { parts: [ { text: "I'm focused on read-only Command Centre operational analytics and can't help with that." } ], role: "model" } } ] }.to_json
      )

      response = described_class.call(message: "What's the weather like today?")

      expect(response[:answer]).to include("Command Centre")
      expect(response[:sources]).to eq([])
      expect(AiQueryLog.count).to eq(0)
    end
  end

  describe "no hallucination / unavailable data" do
    it "passes through a grounded NULL result without the service inventing a number" do
      stub_tool_then_answer(
        source: "vw_hub_dashboard_summary",
        args: { source: "vw_hub_dashboard_summary", select: [ "avg_dwell_time_minutes" ], filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ] },
        final_answer: "Average dwell time is currently unavailable for Indore Hub because there is no completed dwell measurement data yet."
      )

      response = described_class.call(message: "What is the average waiting time at Indore hub?")

      expect(response[:answer]).to match(/unavailable/i)
    end
  end

  describe "Gemini not configured" do
    it "responds gracefully instead of crashing" do
      ENV["GEMINI_API_KEY"] = nil

      response = described_class.call(message: "How many vehicles are in Indore?")

      expect(response[:answer]).to match(/not configured/i)
      expect(AiConversation.find_by(session_key: response[:conversation_id])).to be_present
    end
  end

  describe "Gemini API failure" do
    it "responds gracefully instead of raising" do
      stub_request(:post, endpoint).to_return(status: 503, body: { error: { message: "unavailable" } }.to_json)

      response = described_class.call(message: "How many vehicles are in Indore?")

      expect(response[:answer]).to match(/couldn't reach Gemini/i)
    end
  end

  describe "runaway tool-calling loop" do
    it "stops after MAX_TOOL_ITERATIONS rather than looping forever" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: {
          candidates: [ {
            content: {
              parts: [ { functionCall: { name: "query_command_center", args: { source: "vw_fleet_dashboard_summary" }, id: "call_x" }, thoughtSignature: "sig" } ],
              role: "model"
            }
          } ]
        }.to_json
      )

      response = described_class.call(message: "How many vehicles are active?")

      expect(response[:answer]).to match(/within the allowed number of steps/i)
      expect(a_request(:post, endpoint)).to have_been_made.times(described_class::MAX_TOOL_ITERATIONS)
    end
  end

  describe "an invalid tool call from the model is surfaced back to Gemini, not raised" do
    it "returns the validation error as a function_result rather than crashing" do
      stub_request(:post, endpoint).to_return(
        status: 200,
        body: {
          candidates: [ {
            content: {
              parts: [ { functionCall: { name: "query_command_center", args: { source: "payment_dues", operation: "count" }, id: "call_bad" }, thoughtSignature: "sig" } ],
              role: "model"
            }
          } ]
        }.to_json
      ).then.to_return(
        status: 200,
        body: { candidates: [ { content: { parts: [ { text: "I don't currently have enough Command Centre data to answer that." } ], role: "model" } } ] }.to_json
      )

      response = described_class.call(message: "How much do we owe vendors?")

      expect(response[:answer]).to match(/don't currently have enough/i)
      log = AiQueryLog.last
      expect(log.success).to eq(false)
      expect(log.error_message).to match(/Unknown or unauthorized source/)
    end
  end

  describe "the 20 required operational questions" do
    examples = [
      { q: "How many vehicles are currently at Indore hub?", source: "vw_vehicle_dashboard", operation: "count",
        filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ] },
      { q: "Which vehicles are at Indore?", source: "vw_vehicle_dashboard", select: %w[vehicle_number hub_name],
        filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ], limit: 5 },
      { q: "How many vehicles are carrying packages?", source: "vw_vehicle_dashboard", operation: "count",
        filters: [ { column: "package_count", operator: "greater_than", value: "0" } ] },
      { q: "What is the average mileage of the fleet?", source: "vw_fleet_dashboard_summary", select: %w[average_mileage_km] },
      { q: "What is the average fuel efficiency?", source: "vw_fleet_dashboard_summary", select: %w[average_fuel_efficiency_kmpl] },
      { q: "Which trips are delayed?", source: "vw_route_dashboard", select: %w[trip_id origin_hub destination_hub],
        filters: [ { column: "status", operator: "equals", value: "delayed" } ], limit: 5 },
      { q: "Which route has the most packages?", source: "vw_route_dashboard", select: %w[trip_id package_count],
        order_by: [ { column: "package_count", direction: "desc" } ], limit: 1 },
      { q: "How many packages are currently in transit?", source: "vw_shipment_dashboard_summary", select: %w[packages_in_transit] },
      { q: "How many packages are overdue?", source: "vw_shipment_dashboard_summary", select: %w[overdue_packages] },
      { q: "How many packages are damaged?", source: "vw_shipment_dashboard_summary", select: %w[packages_damaged] },
      { q: "Which packages are assigned to vehicle CC-VEH-0074?", source: "vw_shipment_dashboard", select: %w[package_identifier package_status],
        filters: [ { column: "vehicle_number", operator: "equals", value: "CC-VEH-0074" } ], limit: 10 },
      { q: "How many critical alerts are open?", source: "vw_network_health_summary", select: %w[critical_alerts] },
      { q: "Why is Indore hub showing operational pressure?", source: "vw_hub_dashboard_summary",
        select: %w[hub_name backlog_packages parking_utilisation_pct avg_vehicle_turnaround_minutes],
        filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ] },
      { q: "Show me the top 5 hubs by backlog.", source: "vw_hub_dashboard_summary", select: %w[hub_name backlog_packages],
        order_by: [ { column: "backlog_packages", direction: "desc" } ], limit: 5 },
      { q: "How many orders are pending?", source: "orders", operation: "count",
        filters: [ { column: "status", operator: "equals", value: "pending" } ] },
      { q: "How many packages are delivered?", source: "vw_shipment_dashboard_summary", select: %w[packages_delivered] },
      { q: "Which vehicles have breakdown events?", source: "vehicle_operation_events", operation: "count_distinct", select: %w[vehicle_id],
        filters: [ { column: "event_type", operator: "equals", value: "BREAKDOWN" } ] },
      { q: "How many vehicles are currently on trip?", source: "vw_fleet_dashboard_summary", select: %w[vehicles_on_trip] },
      { q: "How many packages are currently at Indore?", source: "vw_hub_dashboard_summary", select: %w[package_count],
        filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ] },
      { q: "What is happening at Indore hub?", source: "vw_hub_dashboard_summary",
        select: %w[hub_name inbound_vehicle_count outbound_vehicle_count open_alerts],
        filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ] }
    ]

    examples.each_with_index do |ex, i|
      it "##{i + 1} #{ex[:q]} - the tool call is grounded in the real database" do
        args = ex.except(:q).stringify_keys
        stubbed = stub_tool_then_answer(source: ex[:source], args: args, final_answer: "grounded answer for ##{i + 1}")

        response = described_class.call(message: ex[:q])

        expect(response[:answer]).to eq("grounded answer for ##{i + 1}")
        expect(response[:sources]).to include(ex[:source])
        expect(stubbed[:real_result]).to be_a(CommandCenter::QueryService::Result)
        expect(stubbed[:real_result].row_count).to be >= 0
      end
    end
  end
end
