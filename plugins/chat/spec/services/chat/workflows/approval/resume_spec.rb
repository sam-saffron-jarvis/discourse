# frozen_string_literal: true

RSpec.describe Chat::Workflows::Approval::Resume do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:execution_id) }

    it "extracts signed action_token details before validation" do
      action_token =
        DiscourseWorkflows::WaitingExecution.action_token(
          execution_id: 123,
          resume_token: "tok-123",
          action: "approve",
        )

      contract = described_class.new(action_token: action_token)
      contract.valid?
      expect(contract.execution_id).to eq(123)
      expect(contract.action_type).to eq("approve")
    end

    it "rejects unrecognized action_type values" do
      action_token =
        DiscourseWorkflows::WaitingExecution.action_token(
          execution_id: 1,
          resume_token: "tok",
          action: "unknown",
        )

      contract = described_class.new(action_token: action_token)
      expect(contract).not_to be_valid
      expect(contract.errors[:action_type]).to be_present
    end
  end

  describe ".call" do
    subject(:result) { described_class.call(params:) }

    fab!(:user)
    fab!(:channel, :chat_channel)

    def approval_action_token(execution_id:, resume_token:, action: "approve")
      DiscourseWorkflows::WaitingExecution.action_token(
        execution_id: execution_id,
        resume_token: resume_token,
        action: action,
      )
    end

    let(:resume_token) { "resume-token" }
    let(:action_type) { "approve" }
    let(:params) { { execution_id:, approved: true, action_token:, channel_id: channel.id } }
    let(:execution_id) { 1 }
    let(:action_token) do
      approval_action_token(
        execution_id: execution_id,
        resume_token: resume_token,
        action: action_type,
      )
    end

    before { SiteSetting.chat_enabled = true }

    context "when plugin is disabled" do
      let(:execution_id) { 1 }
      let(:resume_token) { "abc" }

      before { SiteSetting.discourse_workflows_enabled = false }

      it { is_expected.to fail_a_policy(:workflows_enabled) }
    end

    context "when contract is invalid" do
      let(:execution_id) { nil }
      let(:action_token) { nil }

      it { is_expected.to fail_a_contract }
    end

    context "when execution does not exist" do
      let(:execution_id) { 999_999 }
      let(:resume_token) { "abc" }

      it { is_expected.to fail_to_find_a_model(:execution) }
    end

    context "when execution is not waiting" do
      fab!(:execution) do
        Fabricate(:discourse_workflows_execution, status: :success, resume_token: "abc")
      end
      let(:execution_id) { execution.id }
      let(:resume_token) { execution.resume_token }

      it { is_expected.to fail_to_find_a_model(:execution) }
    end

    context "when action_token does not match" do
      fab!(:execution) do
        Fabricate(:discourse_workflows_execution, status: :waiting, resume_token: "correct-token")
      end
      let(:execution_id) { execution.id }
      let(:action_token) do
        approval_action_token(
          execution_id: execution.id,
          resume_token: "wrong-token",
          action: "approve",
        )
      end

      it { is_expected.to fail_to_find_a_model(:execution) }
    end

    context "when action_type is missing" do
      let(:execution_id) { 1 }
      let(:action_token) { "correct-token" }

      it { is_expected.to fail_a_contract }
    end

    context "when action_type is unrecognized" do
      let(:execution_id) { 1 }
      let(:resume_token) { "correct-token" }
      let(:action_type) { "unknown" }

      it { is_expected.to fail_a_contract }
    end

    context "when the execution cannot be claimed" do
      fab!(:workflow) do
        graph =
          build_workflow_graph do |g|
            g.node "trigger-1", "trigger:manual"
            g.node "wait-1",
                   "action:chat_approval",
                   configuration: {
                     "message" => "Approve?",
                     "channel_id" => channel.id.to_s,
                   }
            g.chain "trigger-1", "wait-1"
          end
        Fabricate(:discourse_workflows_workflow, created_by: user, **graph).tap do |wf|
          publish_workflow!(wf)
        end
      end
      let(:execution) { DiscourseWorkflows::Executor.new(workflow, "trigger-1", {}).run }
      let(:execution_id) { execution.id }
      let(:resume_token) { execution.resume_token }

      before do
        allow(::DiscourseWorkflows::Execution).to receive(:claim_for_resume).and_return(nil)
      end

      it { is_expected.to fail_to_find_a_model(:claimed_execution) }
    end

    context "when everything is valid" do
      fab!(:workflow) do
        graph =
          build_workflow_graph do |g|
            g.node "trigger-1", "trigger:manual", name: "Manual"
            g.node "wait-1",
                   "action:chat_approval",
                   name: "Wait",
                   configuration: {
                     "message" => "Approve?",
                     "channel_id" => channel.id.to_s,
                   }
            g.chain "trigger-1", "wait-1"
          end
        Fabricate(:discourse_workflows_workflow, created_by: user, **graph).tap do |wf|
          publish_workflow!(wf)
        end
      end

      let(:execution) { DiscourseWorkflows::Executor.new(workflow, "trigger-1", {}).run }
      let(:execution_id) { execution.id }
      let(:resume_token) { execution.resume_token }

      it { is_expected.to run_successfully }

      it "resumes the execution" do
        result
        expect(execution.reload.status).to eq("success")
      end

      context "when denied" do
        let(:action_type) { "deny" }
        let(:params) { { execution_id:, approved: false, action_token:, channel_id: channel.id } }

        it { is_expected.to run_successfully }

        it "resumes the execution as denied" do
          result
          expect(execution.reload.status).to eq("success")
        end
      end
    end
  end
end
