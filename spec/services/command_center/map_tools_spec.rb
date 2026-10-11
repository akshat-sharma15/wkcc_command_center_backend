require "rails_helper"

RSpec.describe CommandCenter::MapTools do
  before(:context) { AiChatFixtures.seed! }
  after(:context) { AiChatFixtures.cleanup! }

  let(:pune_code) { "#{AiChatFixtures::HUB_CODE_PREFIX}PUN" }
  let(:pune) { Hub.find_by!(code: pune_code) }

  it "lists exactly the vehicles the map shows for a hub's inbound filter" do
    map_numbers = FleetMonitoring::HubVehicleFlow.rows(pune, "inbound").map { |r| r[:vehicle_number] }
    expect(map_numbers).not_to be_empty

    payload = described_class.call("map_hub_vehicles", { "hub" => pune_code, "direction" => "inbound" })[:payload]

    expect(payload[:count]).to eq(map_numbers.size)
    expect(payload[:vehicles].map { |v| v[:vehicle_number] }).to match_array(map_numbers)
    expect(payload[:vehicles].map { |v| v[:vehicle_number] }).not_to include("#{AiChatFixtures::VEHICLE_NUMBER_PREFIX}99") # off-map truck
  end

  it "finds a hub by name as well as code" do
    payload = described_class.call("map_hub_vehicles", { "hub" => "Pune AI-Test" })[:payload]
    expect(payload[:hub_code]).to eq(pune_code)
  end

  it "returns the hub card the map shows" do
    payload = described_class.call("map_hub_summary", { "hub" => pune_code })[:payload]
    expect(payload).to eq(FleetMonitoring::HubPresenter.new(pune).as_json.except(:lat, :lng))
  end

  it "returns a map vehicle, and nothing for an off-map one" do
    number = "#{AiChatFixtures::VEHICLE_NUMBER_PREFIX}04"
    expect(described_class.call("map_vehicle", { "vehicle_number" => number })[:payload][:pnr]).to eq(number)
    expect(described_class.call("map_vehicle", { "vehicle_number" => "#{AiChatFixtures::VEHICLE_NUMBER_PREFIX}99" })[:error]).to match(/No vehicle/)
  end

  it "counts the fleet by the map's own status" do
    payload = described_class.call("map_fleet", { "status" => "MAINTENANCE" })[:payload]
    expect(payload[:total_vehicles]).to eq(Vehicle.fleet_monitoring_poc.count)
    expect(payload[:vehicles].map { |v| v[:status] }.uniq).to eq([ "MAINTENANCE" ])
    expect(payload[:matching_count]).to eq(payload[:counts_by_status]["MAINTENANCE"])
  end

  it "reports an unknown hub as an error for the model, not an exception" do
    expect(described_class.call("map_hub_vehicles", { "hub" => "No Such Hub" })[:error]).to match(/No hub matching/)
  end

  it "runs read-only: a write inside the lookup is rejected by Postgres" do
    expect {
      described_class.send(:read_only) { OperationsRecord.connection.execute("UPDATE hubs SET name = name WHERE id = #{pune.id}") }
    }.to raise_error(ActiveRecord::StatementInvalid, /read-only transaction/)
  end
end
