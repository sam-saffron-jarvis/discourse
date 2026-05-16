# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Workflow::ManualExecute do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:trigger_node_id) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:admin)
    fab!(:workflow) do
      graph = build_workflow_graph { |g| g.node "trigger-1", "trigger:manual" }
      Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **graph)
    end

    let(:params) { { workflow_id: workflow.id, trigger_node_id: "trigger-1" } }
    let(:dependencies) { { guardian: admin.guardian } }

    context "when contract is invalid" do
      let(:params) { super().merge(trigger_node_id: nil) }

      it { is_expected.to fail_a_contract }
    end

    context "when user cannot manage workflows" do
      fab!(:user)

      let(:dependencies) { { guardian: user.guardian } }

      it { is_expected.to fail_a_policy(:can_manage_workflows) }
    end

    context "when workflow does not exist" do
      let(:params) { super().merge(workflow_id: -1) }

      it { is_expected.to fail_to_find_a_model(:workflow) }
    end

    context "when trigger node does not exist" do
      let(:params) { super().merge(trigger_node_id: "nonexistent") }

      it { is_expected.to fail_to_find_a_model(:trigger_node) }
    end

    context "when everything is valid" do
      it { is_expected.to run_successfully }

      it "delegates execution to Workflow::Execute" do
        expect { result }.to change { DiscourseWorkflows::Execution.count }.by(1)
      end

      it "records a manual execution mode" do
        result
        expect(result[:execution]).to be_manual
      end

      context "when manually testing an Error trigger" do
        fab!(:workflow) do
          graph = build_workflow_graph { |g| g.node "trigger-1", "trigger:error" }
          Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **graph)
        end

        it "uses n8n-style mock error data" do
          result

          expect(result[:execution].trigger_data).to include(
            "execution" =>
              include(
                "error" => include("message" => "Example Error Message"),
                "lastNodeExecuted" => "Node With Error",
                "mode" => "manual",
              ),
            "workflow" => include("id" => workflow.id.to_s, "name" => workflow.name),
          )
        end
      end
    end
  end
end
