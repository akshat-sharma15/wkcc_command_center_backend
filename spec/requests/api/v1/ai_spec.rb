require "rails_helper"

RSpec.describe "Api::V1::Ai", type: :request do
  before(:context) { AiChatFixtures.seed! }
  after(:context) { AiChatFixtures.cleanup! }

  let(:endpoint) { "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent" }

  around do |example|
    original = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-key"
    example.run
    ENV["GEMINI_API_KEY"] = original
  end

  def stub_tool_then_answer(args:, final_answer:, call_id: "call_1")
    stub_request(:post, endpoint)
      .to_return(
        status: 200,
        body: {
          candidates: [ {
            content: {
              parts: [ { functionCall: { name: "query_command_center", args: args, id: call_id }, thoughtSignature: "fake-sig" } ],
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

  describe "POST /api/v1/ai/chat" do
    it "returns answer, conversation_id, and sources - never generated SQL" do
      stub_tool_then_answer(
        args: { source: "vw_vehicle_dashboard", operation: "count", filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ] },
        final_answer: "There are 11 vehicles currently assigned to Indore Hub."
      )

      post "/api/v1/ai/chat", params: { message: "How many vehicles are currently at Indore hub?" }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["answer"]).to eq("There are 11 vehicles currently assigned to Indore Hub.")
      expect(body["conversation_id"]).to be_present
      expect(body["sources"]).to eq([ "vw_vehicle_dashboard" ])
      expect(body.keys).not_to include("sql", "query", "structured_query")
    end

    it "continues an existing conversation when conversation_id is supplied" do
      stub_tool_then_answer(
        args: { source: "vw_vehicle_dashboard", operation: "count", filters: [ { column: "hub_name", operator: "contains", value: "Indore" } ] },
        final_answer: "There are 11 vehicles at Indore."
      )
      post "/api/v1/ai/chat", params: { message: "How many vehicles are in Indore?" }, as: :json
      conversation_id = response.parsed_body["conversation_id"]

      stub_tool_then_answer(
        args: { source: "vw_vehicle_dashboard", operation: "count",
                filters: [ { column: "hub_name", operator: "contains", value: "Indore" }, { column: "package_count", operator: "greater_than", value: "0" } ] },
        final_answer: "8 of them are carrying packages."
      )
      post "/api/v1/ai/chat", params: { message: "How many of them have packages?", conversation_id: conversation_id }, as: :json

      expect(response.parsed_body["conversation_id"]).to eq(conversation_id)
      expect(response.parsed_body["answer"]).to eq("8 of them are carrying packages.")
    end

    it "returns 422 when message is missing" do
      post "/api/v1/ai/chat", params: {}, as: :json
      expect(response).to have_http_status(:bad_request).or have_http_status(:unprocessable_content)
    end

    it "never echoes GEMINI_API_KEY anywhere in the response" do
      stub_tool_then_answer(args: { source: "hubs", operation: "count" }, final_answer: "There are 47 hubs.")
      post "/api/v1/ai/chat", params: { message: "How many hubs?" }, as: :json

      expect(response.body).not_to include("test-key")
    end
  end
end
