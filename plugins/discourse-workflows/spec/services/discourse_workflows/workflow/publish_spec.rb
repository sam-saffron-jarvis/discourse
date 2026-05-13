# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Workflow::Publish do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:workflow_id) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:user, :admin)
    fab!(:workflow) { Fabricate(:discourse_workflows_workflow, created_by: user) }

    let(:params) { { workflow_id: workflow.id } }
    let(:dependencies) { { guardian: user.guardian } }

    context "when workflow is not found" do
      let(:params) { { workflow_id: -1 } }

      it { is_expected.to fail_to_find_a_model(:workflow) }
    end

    context "when user cannot manage workflows" do
      fab!(:non_admin, :user)

      let(:dependencies) { { guardian: non_admin.guardian } }

      it { is_expected.to fail_a_policy(:can_manage_workflows) }
    end

    context "when workflow has no draft version" do
      before { workflow.update_columns(draft_version_id: nil) }

      it { is_expected.to fail_to_find_a_model(:draft_version) }
    end

    context "when everything's ok" do
      it { is_expected.to run_successfully }

      it "publishes the current draft version" do
        result
        expect(workflow.reload.published_version_id).to eq(workflow.draft_version_id)
      end

      it "clears workflow caches" do
        Site.expects(:clear_cache).once
        DiscourseWorkflows::WorkflowDependency.expects(:clear_cache!).once
        result
      end

      it "prunes static_data for nodes removed from the published draft" do
        last_triggered_at = 1.minute.ago.iso8601
        graph = build_workflow_graph { |g| g.node "kept-trigger", "trigger:schedule" }
        workflow.update!(
          nodes: graph[:nodes],
          connections: graph[:connections],
          static_data: {
            "kept-trigger" => {
              "seconds_last_triggered" => {
                "0" => last_triggered_at,
              },
            },
            "removed-trigger" => {
              "seconds_tokens" => {
                "0" => "removed-token",
              },
            },
          },
        )
        workflow.draft_version.update!(nodes: graph[:nodes], connections: graph[:connections])

        result

        expect(workflow.reload.static_data).to eq(
          "kept-trigger" => {
            "seconds_last_triggered" => {
              "0" => last_triggered_at,
            },
          },
        )
      end
    end
  end
end
