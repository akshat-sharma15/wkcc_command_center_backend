require "rails_helper"

# Chart-scoped AI chat. This endpoint is called by Superset (server-to-server)
# after Superset has resolved a chart id to a chart + dataset under the
# signed-in user's own permissions - never by the browser. The specs below
# cover the two properties that makes safe: the service token gate, and the
# dataset allow-list that keeps a chart conversation off every other source.
RSpec.describe "Api::V1::Ai chart chat", type: :request do
  before(:context) { AiChatFixtures.seed! }
  after(:context) { AiChatFixtures.cleanup! }

  let(:model) { ENV.fetch("GEMINI_MODEL", GeminiClient::DEFAULT_MODEL) }
  let(:endpoint) { "https://generativelanguage.googleapis.com/v1beta/models/#{model}:generateContent" }
  let(:service_token) { "test-service-token" }
  let(:headers) { { "X-Command-Center-Service-Token" => service_token } }

  # Mirrors what superset/chart_chat/api.py assembles from a Slice and its
  # dataset before calling this endpoint.
  let(:context) do
    {
      chart: {
        id: 42,
        name: "Total Vehicles",
        viz_type: "big_number_total",
        description: "Fleet size across the network",
        dashboards: [ "Fleet / Vehicles / Routes" ],
        query: { metrics: [ "count" ], time_range: "No filter" }
      },
      dataset: {
        id: 7,
        name: "vw_vehicle_dashboard",
        database_name: "wkcc_ops",
        columns: [ { name: "hub_name", type: "VARCHAR" }, { name: "status", type: "VARCHAR" } ],
        metrics: [ { name: "count" } ]
      }
    }
  end

  around do |example|
    original_key = ENV["GEMINI_API_KEY"]
    original_token = ENV["COMMAND_CENTER_SERVICE_TOKEN"]
    ENV["GEMINI_API_KEY"] = "test-key"
    ENV["COMMAND_CENTER_SERVICE_TOKEN"] = service_token
    example.run
    ENV["GEMINI_API_KEY"] = original_key
    ENV["COMMAND_CENTER_SERVICE_TOKEN"] = original_token
  end

  def stub_tool_then_answer(args:, final_answer:)
    stub_request(:post, endpoint)
      .to_return(
        status: 200,
        body: {
          candidates: [ {
            content: {
              parts: [ { functionCall: { name: "query_command_center", args: args, id: "call_1" }, thoughtSignature: "fake-sig" } ],
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
  end

  def stub_answer(text)
    stub_request(:post, endpoint).to_return(
      status: 200,
      body: { candidates: [ { content: { parts: [ { text: text } ], role: "model" } } ] }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  describe "service token gate" do
    it "refuses a request with no service token - a browser cannot supply its own context" do
      post "/api/v1/ai/chart_chat", params: { context: context }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(WebMock).not_to have_requested(:post, endpoint)
    end

    it "refuses a request with the wrong service token" do
      post "/api/v1/ai/chart_chat", params: { context: context }, as: :json,
           headers: { "X-Command-Center-Service-Token" => "not-the-token" }

      expect(response).to have_http_status(:forbidden)
      expect(WebMock).not_to have_requested(:post, endpoint)
    end

    it "refuses every request when no token is configured, rather than opening up" do
      ENV["COMMAND_CENTER_SERVICE_TOKEN"] = ""

      post "/api/v1/ai/chart_chat", params: { context: context }, as: :json, headers: headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "opening a session" do
    it "summarises the chart automatically when no message is given" do
      stub_tool_then_answer(
        args: { source: "vw_vehicle_dashboard", operation: "count" },
        final_answer: "Total Vehicles reports 11 vehicles across the network."
      )

      post "/api/v1/ai/chart_chat", params: { context: context }, as: :json, headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["answer"]).to eq("Total Vehicles reports 11 vehicles across the network.")
      expect(body["conversation_id"]).to be_present
      expect(body["sources"]).to eq([ "vw_vehicle_dashboard" ])
    end

    it "binds the conversation to the chart it was opened for" do
      stub_answer("Summary.")
      post "/api/v1/ai/chart_chat", params: { context: context }, as: :json, headers: headers

      conversation = AiConversation.find_by(session_key: response.parsed_body["conversation_id"])
      expect(conversation.scope_key).to eq("chart:42")
    end

    it "requires a chart id in the context" do
      post "/api/v1/ai/chart_chat", params: { context: { chart: {}, dataset: nil } }, as: :json, headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "dataset scoping" do
    it "tells the model it may only query the chart's own dataset" do
      stub_answer("Summary.")

      post "/api/v1/ai/chart_chat", params: { context: context }, as: :json, headers: headers

      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        instruction = JSON.parse(request.body).dig("systemInstruction", "parts", 0, "text")
        instruction.include?('source="vw_vehicle_dashboard"') &&
          instruction.include?("CHART-SCOPED CONVERSATION")
      }
    end

    it "blocks a tool call against any other source, even when the model asks for one" do
      stub_tool_then_answer(
        args: { source: "vw_hub_dashboard_summary", operation: "count" },
        final_answer: "I can only answer from this chart's dataset."
      )

      post "/api/v1/ai/chart_chat", params: { context: context }, as: :json, headers: headers

      expect(response).to have_http_status(:ok)
      # The blocked source is never reported as a source that was used...
      expect(response.parsed_body["sources"]).not_to include("vw_hub_dashboard_summary")
      # ...and the model is told why, so it can correct itself in-scope.
      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        body = JSON.parse(request.body)
        body["contents"].to_json.include?("This conversation is scoped to the chart's dataset")
      }
    end

    it "refuses to query at all when the chart's dataset is not an approved source" do
      unapproved = context.deep_dup
      unapproved[:dataset][:name] = "some_unapproved_table"
      stub_answer("This chart's dataset isn't available for querying.")

      post "/api/v1/ai/chart_chat", params: { context: unapproved }, as: :json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(WebMock).to have_requested(:post, endpoint).with { |request|
        instruction = JSON.parse(request.body).dig("systemInstruction", "parts", 0, "text")
        instruction.include?("do\nNOT call query_command_center") ||
          instruction.include?("do NOT call query_command_center")
      }
    end
  end

  describe "follow-up questions" do
    it "keeps answering within the same chart's dataset across turns" do
      stub_answer("Summary.")
      post "/api/v1/ai/chart_chat", params: { context: context }, as: :json, headers: headers
      conversation_id = response.parsed_body["conversation_id"]

      stub_tool_then_answer(
        args: { source: "vw_vehicle_dashboard", operation: "count", group_by: [ "hub_name" ] },
        final_answer: "Indore has the most vehicles."
      )
      post "/api/v1/ai/chart_chat",
           params: { context: context, message: "Which hub has the most vehicles?", conversation_id: conversation_id },
           as: :json, headers: headers

      expect(response.parsed_body["conversation_id"]).to eq(conversation_id)
      expect(response.parsed_body["answer"]).to eq("Indore has the most vehicles.")
    end

    it "does not let one chart's conversation be replayed for a different chart" do
      stub_answer("Summary.")
      post "/api/v1/ai/chart_chat", params: { context: context }, as: :json, headers: headers
      chart_a_conversation = response.parsed_body["conversation_id"]

      other_chart = context.deep_dup
      other_chart[:chart][:id] = 99
      other_chart[:chart][:name] = "Total Packages"

      stub_answer("Summary of the other chart.")
      post "/api/v1/ai/chart_chat",
           params: { context: other_chart, message: "What is this?", conversation_id: chart_a_conversation },
           as: :json, headers: headers

      # A fresh conversation is issued rather than chart A's history being reused.
      expect(response.parsed_body["conversation_id"]).not_to eq(chart_a_conversation)
      expect(AiConversation.find_by(session_key: response.parsed_body["conversation_id"]).scope_key).to eq("chart:99")
    end

    it "does not let a global-chat conversation be reused as a chart conversation" do
      stub_answer("Global answer.")
      post "/api/v1/ai/chat", params: { message: "How many hubs?" }, as: :json
      global_conversation = response.parsed_body["conversation_id"]

      stub_answer("Chart summary.")
      post "/api/v1/ai/chart_chat",
           params: { context: context, conversation_id: global_conversation },
           as: :json, headers: headers

      expect(response.parsed_body["conversation_id"]).not_to eq(global_conversation)
    end
  end

  it "never echoes the service token or API key back to the caller" do
    stub_answer("Summary.")

    post "/api/v1/ai/chart_chat", params: { context: context }, as: :json, headers: headers

    expect(response.body).not_to include(service_token)
    expect(response.body).not_to include("test-key")
  end
end
