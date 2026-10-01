require "rails_helper"

RSpec.describe DurationFormat do
  it "keeps under an hour in minutes and converts an hour or more to hours" do
    expect(described_class.minutes(45)).to eq("45 min")
    expect(described_class.minutes(60)).to eq("1 hour")
    expect(described_class.minutes(90)).to eq("1.5 hours")
    expect(described_class.minutes(149, signed: true)).to eq("+2.5 hours")
    expect(described_class.minutes(-90, signed: true)).to eq("-1.5 hours")
    expect(described_class.minutes(nil)).to be_nil
  end

  it "normalizes stored '+N min' text" do
    expect(described_class.normalize_text("(+14 km, +90 min). Wait +30 min")).to eq("(+14 km, +1.5 hours). Wait +30 min")
  end

  it "is what the incident card shows for a 90 minute delay" do
    alert = create(:alert, metadata: { "incident" => { "key" => "vehicle.failure", "title" => "Truck Failure", "delay_minutes" => 90, "summary" => "Delayed +90 min." } })
    card = IncidentNotificationPresenter.new(alert).as_json
    expect(card[:fields]).to include({ label: "ETA delay", value: "+1.5 hours" })
    expect(card[:delay_label]).to eq("+1.5 hours")
    expect(card[:summary]).to eq("Delayed +1.5 hours.")
  end
end
