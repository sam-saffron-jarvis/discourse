# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Workflow::Update do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:workflow_id) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:user, :admin)
    fab!(:workflow) { Fabricate(:discourse_workflows_workflow, created_by: user) }

    let(:params) do
      attrs = { workflow_id: workflow.id, name:, error_workflow_id:, nodes:, connections: }
      attrs[:timezone] = timezone unless timezone == :not_provided
      attrs
    end
    let(:dependencies) { { guardian: user.guardian } }
    let(:name) { "Updated Workflow" }
    let(:error_workflow_id) { nil }
    let(:timezone) { :not_provided }
    let(:nodes) { [] }
    let(:connections) { [] }

    context "when contract is invalid" do
      let(:name) { nil }

      it { is_expected.to fail_a_contract }
    end

    context "when name is too long" do
      let(:name) { "a" * 101 }

      it { is_expected.to fail_a_contract }
    end

    context "when workflow is not found" do
      let(:params) { { workflow_id: -1, name: "Updated Workflow" } }

      it { is_expected.to fail_to_find_a_model(:workflow) }
    end

    context "when user cannot manage workflows" do
      fab!(:non_admin, :user)

      let(:dependencies) { { guardian: non_admin.guardian } }

      it { is_expected.to fail_a_policy(:can_manage_workflows) }
    end

    context "when error workflow is invalid" do
      let(:error_workflow_id) { -1 }

      it { is_expected.to fail_with_an_invalid_model(:workflow) }
    end

    context "when the workflow handles its own errors" do
      let(:error_workflow_id) { workflow.id }

      it { is_expected.to run_successfully }

      it "sets itself as the error workflow" do
        result
        expect(workflow.reload.error_workflow_id).to eq(workflow.id)
      end
    end

    context "when timezone is invalid" do
      let(:timezone) { "Mars/Olympus" }

      it { is_expected.to fail_a_contract }
    end

    context "when graph population fails" do
      let(:nodes) { [{ client_id: "node_1", type: "trigger:manual", name: "Manual" }] }

      before { DiscourseWorkflows::Workflow::Action::PopulateGraph.stubs(:call).returns(false) }

      it { is_expected.to fail_a_step(:populate_graph) }
    end

    context "when no graph data is provided" do
      let(:nodes) { nil }
      let(:connections) { nil }

      before do
        extra = build_workflow_graph { |g| g.node "existing-1", "trigger:manual", name: "Existing" }
        workflow.update!(nodes: extra[:nodes])
      end

      it { is_expected.to run_successfully }

      it "preserves existing nodes" do
        result
        expect(workflow.reload.nodes.size).to eq(1)
      end

      context "when the workflow is already published" do
        before { publish_workflow!(workflow) }

        it "creates a new draft version for metadata changes" do
          published_version_id = workflow.published_version_id

          result
          workflow.reload

          expect(workflow.draft_version_id).not_to eq(published_version_id)
          expect(workflow.published_version_id).to eq(published_version_id)
          expect(workflow.draft_version.name).to eq("Updated Workflow")
        end

        it "does not mutate the published version metadata" do
          published_version_id = workflow.published_version_id
          published_version_name = workflow.published_version.name

          result

          expect(DiscourseWorkflows::WorkflowVersion.find(published_version_id).name).to eq(
            published_version_name,
          )
        end
      end

      it "fetches the workflow after acquiring the lock" do
        lock_sequence = sequence("workflow update lock")

        DistributedMutex
          .expects(:synchronize)
          .with("discourse_workflows/workflow/update:workflow_id:#{workflow.id}")
          .in_sequence(lock_sequence)
          .yields
        DiscourseWorkflows::Workflow
          .expects(:find_by)
          .with(id: workflow.id)
          .in_sequence(lock_sequence)
          .returns(workflow)

        result
      end

      context "when the workflow has no draft version" do
        before { workflow.update_columns(draft_version_id: nil) }

        it { is_expected.to fail_to_find_a_model(:draft_version) }
      end
    end

    context "when everything's ok" do
      before { publish_workflow!(workflow) }

      let(:nodes) do
        [
          {
            client_id: "node_1",
            type: "trigger:topic_created",
            name: "Topic Created",
            parameters: {
              category_id: 1,
            },
          },
          {
            client_id: "node_2",
            type: "action:topic_tags",
            name: "Topic Tags",
            parameters: {
              tag_names: "test",
            },
          },
        ]
      end
      let(:connections) do
        [{ source_client_id: "node_1", target_client_id: "node_2", source_output_index: 0 }]
      end

      it { is_expected.to run_successfully }

      it "updates the workflow attributes" do
        result
        workflow.reload
        expect(workflow).to have_attributes(name: "Updated Workflow")
        expect(workflow).to be_published
      end

      context "with a workflow timezone" do
        let(:timezone) { "Europe/Paris" }

        it "stores the timezone in workflow settings" do
          result

          expect(workflow.reload.settings).to include("timezone" => "Europe/Paris")
          expect(workflow.draft_version.settings).to include("timezone" => "Europe/Paris")
        end
      end

      it "populates the workflow graph" do
        result
        workflow.reload
        expect(workflow.nodes.size).to eq(2)
        expect(workflow.connections.size).to eq(1)
      end

      it "creates an unpublished draft version" do
        published_version_id = workflow.published_version_id
        result
        workflow.reload
        expect(workflow.draft_version_id).not_to eq(published_version_id)
        expect(workflow.published_version_id).to eq(published_version_id)
        expect(workflow).to have_unpublished_changes
      end

      it "locks draft version creation for the workflow" do
        DistributedMutex
          .expects(:synchronize)
          .with("discourse_workflows/workflow/update:workflow_id:#{workflow.id}")
          .yields

        result
      end

      it "clears the site cache" do
        Site.expects(:clear_cache).once
        result
      end

      context "when graph data includes schedule triggers" do
        let(:nodes) do
          [
            {
              client_id: "node_1",
              type: "trigger:schedule",
              name: "Schedule",
              parameters: {
                rule: {
                  interval: [{ field: "minutes", minutesInterval: 5 }],
                },
              },
            },
          ]
        end
        let(:connections) { [] }

        it "does not activate triggers before publishing" do
          DiscourseWorkflows::TriggerRuntime.expects(:activate_workflow!).never
          result
        end
      end
    end
  end
end
