require "rails_helper"

RSpec.describe "POST /api/v1/ai/chat with Fleet Map context", type: :request do
  let(:reply) { { answer: "ok", conversation_id: "c1", sources: [] } }

  it "passes a sanitized map context to the existing chat service" do
    allow(CommandCenter::AiChatService).to receive(:call).and_return(reply)

    post "/api/v1/ai/chat", params: {
      message: "Where is this truck going?",
      context: { source: "fleet_map", selected_vehicle: { vehicle_number: "MP09PX8893", vehicle_id: 7 } }
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(CommandCenter::AiChatService).to have_received(:call) do |message:, session_key:, map_context:|
      expect(message).to eq("Where is this truck going?")
      expect(map_context.selections["selected_vehicle"]["vehicle_number"]).to eq("MP09PX8893")
    end
  end

  it "leaves the dashboard request (no context) exactly as before" do
    allow(CommandCenter::AiChatService).to receive(:call).and_return(reply)

    post "/api/v1/ai/chat", params: { message: "How many hubs do we have?", conversation_id: "abc" }, as: :json

    expect(CommandCenter::AiChatService).to have_received(:call).with(message: "How many hubs do we have?", session_key: "abc", map_context: nil)
  end

  it "uses the context only in that turn's system instruction" do
    service = CommandCenter::AiChatService.new(
      message: "How many trucks are coming here?",
      map_context: CommandCenter::MapContext.from_params("source" => "fleet_map", "selected_hub" => { "code" => "CC-HUB-016", "name" => "Indore" })
    )
    expect(service.send(:system_instruction)).to start_with(CommandCenter::AiChatService::SYSTEM_INSTRUCTIONS)
    expect(service.send(:system_instruction)).to include("Selected hub: Indore, code CC-HUB-016")
    expect(CommandCenter::AiChatService.new(message: "hi").send(:system_instruction)).to eq(CommandCenter::AiChatService::SYSTEM_INSTRUCTIONS)
  end
end
