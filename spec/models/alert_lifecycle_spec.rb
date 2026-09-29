require "rails_helper"

RSpec.describe Alert, "assignment and lifecycle", type: :model do
  let(:rule) do
    create(:alert_rule, primary_assignee_type: "user", primary_assignee_id: 7,
                        secondary_assignee_type: "role", secondary_assignee_id: 3, escalation_after_minutes: 15)
  end
  let(:alert) { create(:alert, alert_rule: rule) }

  it "is assigned to the rule's primary point of contact on creation" do
    expect(alert.assignee).to eq(type: "user", id: 7)
    expect(alert.assignment_level).to eq("primary")
    expect(alert.escalation_due_at).to be_within(1.second).of(alert.triggered_at + 15.minutes)
  end

  it "acknowledges, reassigns, escalates and resolves, keeping a history" do
    alert.acknowledge!(by: 1)
    expect(alert).to be_status_acknowledged
    expect(alert.acknowledged_by).to eq(1)

    alert.assign!(assignee_type: "user", assignee_id: 9, by: 1)
    expect(alert.assignee).to eq(type: "user", id: 9)

    expect(alert).to be_status_in_progress

    alert.escalate!(by: 1)
    expect(alert.assignee).to eq(type: "role", id: 3)
    expect(alert).to be_status_escalated
    expect(alert.escalation_level).to eq(1)
    expect(alert.metadata["history"].last["to"]).to eq("type" => "role", "id" => 3)

    alert.resolve!(by: 2, note: "Replacement vehicle assigned.")
    expect(alert.reload).to be_status_resolved
    expect(alert.resolved_by).to eq(2)
    expect(alert.resolution_note).to eq("Replacement vehicle assigned.")
    expect(alert.metadata["history"].map { |entry| entry["action"] }).to eq(%w[acknowledged reassigned escalated resolved])
    expect(alert.metadata["history"][1]["from"]).to eq("type" => "user", "id" => 7)
  end

  it "refuses invalid transitions" do
    alert.resolve!(by: 1)
    expect { alert.acknowledge!(by: 1) }.to raise_error(Alert::TransitionError)
    expect { alert.escalate!(by: 1) }.to raise_error(Alert::TransitionError)
  end

  it "refuses to escalate twice or without a secondary" do
    alert.escalate!(by: 1)
    expect { alert.escalate!(by: 1) }.to raise_error(Alert::TransitionError, /already escalated/)

    plain = create(:alert, alert_rule: create(:alert_rule))
    expect { plain.escalate!(by: 1) }.to raise_error(Alert::TransitionError, /no secondary/)
  end
end
