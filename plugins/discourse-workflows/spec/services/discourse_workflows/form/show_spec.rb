# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Form::Show do
  describe described_class::Contract, type: :model do
    it "requires uuid for initial form requests" do
      contract = described_class.new
      expect(contract).not_to be_valid
      expect(contract.errors[:uuid]).to be_present
    end

    it "allows waiting execution requests without uuid" do
      contract = described_class.new(execution_id: 1, signature: "token")
      contract.valid?
      expect(contract.errors[:uuid]).to be_blank
    end

    it "requires signature for waiting execution requests" do
      contract = described_class.new(execution_id: 1)
      expect(contract).not_to be_valid
      expect(contract.errors[:signature]).to be_present
    end
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:user)
    fab!(:workflow) do
      graph =
        build_workflow_graph do |g|
          g.node "trigger-1",
                 "trigger:form",
                 configuration: {
                   "uuid" => "a1b2c3d4-e5f6-7890-abcd-ef0123456789",
                   "form_title" => "Test Form",
                   "form_description" => "A test form",
                   "form_fields" => [
                     { "field_label" => "Name", "field_type" => "text", "required" => true },
                   ],
                   "response_mode" => "on_received",
                 }
        end
      Fabricate(:discourse_workflows_workflow, published: true, **graph)
    end

    let(:dependencies) { { guardian: Guardian.new(user) } }
    let(:uuid) { "a1b2c3d4-e5f6-7890-abcd-ef0123456789" }
    let(:params) { { uuid: uuid } }

    before { DiscourseWorkflows::WorkflowDependencyIndexer.call(workflow) }

    context "when contract is invalid" do
      let(:uuid) { nil }

      it { is_expected.to fail_a_contract }
    end

    context "when workflow is not found" do
      let(:uuid) { "00000000-0000-0000-0000-000000000000" }

      it { is_expected.to fail_to_find_a_model(:published_trigger) }
    end

    context "when workflow is unpublished" do
      before { unpublish_workflow!(workflow) }

      it { is_expected.to fail_to_find_a_model(:published_trigger) }
    end

    context "when the form requires a logged-in user" do
      before do
        trigger_node = workflow.nodes.find { |n| n["type"] == "trigger:form" }
        trigger_node["parameters"]["authentication"] = "login_required"
        workflow.update!(nodes: workflow.nodes)
        publish_workflow!(workflow)
      end

      context "without a current user" do
        let(:dependencies) { { guardian: Guardian.new } }

        it { is_expected.to fail_a_policy(:authenticated_if_required) }
      end

      context "with a current user" do
        it { is_expected.to run_successfully }
      end
    end

    context "with an initial form request" do
      it { is_expected.to run_successfully }

      it "builds trigger form data" do
        result
        form_data = result[:form_data]
        expect(form_data[:uuid]).to eq(uuid)
        expect(form_data[:form_title]).to eq("Test Form")
        expect(form_data[:form_description]).to eq("A test form")
        expect(form_data[:form_fields]).to eq(
          [
            {
              "field_label" => "Name",
              "field_type" => "text",
              "required" => true,
              "key" => "name",
            },
          ],
        )
        expect(form_data[:response_mode]).to eq("on_received")
        expect(form_data[:has_downstream_form]).to be(false)
      end

      it "returns a signed submission token without creating a waiting execution" do
        expect { result }.not_to change { DiscourseWorkflows::Execution.waiting.count }

        expect(result[:form_data][:resume_token]).to be_present
        expect(
          DiscourseWorkflows::FormTriggerToken.valid?(
            result[:form_data][:resume_token],
            workflow_id: workflow.id,
            trigger_node_id: "trigger-1",
            uuid: uuid,
          ),
        ).to be(true)
      end

      context "with URL query parameters" do
        let(:params) do
          { uuid: uuid, form_query_parameters: { "name" => "Query User", "source" => "email" } }
        end

        it "uses matching query parameters as field defaults" do
          expect(result[:form_data][:form_fields].first["default_value"]).to eq("Query User")
        end

        it "persists query parameters in the signed submission token" do
          token_payload =
            DiscourseWorkflows::FormTriggerToken.payload(
              result[:form_data][:resume_token],
              workflow_id: workflow.id,
              trigger_node_id: "trigger-1",
              uuid: uuid,
            )

          expect(token_payload["form_query_parameters"]).to eq(
            "name" => "Query User",
            "source" => "email",
          )
        end
      end

      context "when the draft workflow name changes after publishing" do
        before do
          trigger_node = workflow.nodes.find { |node| node["id"] == "trigger-1" }
          trigger_node["parameters"]["form_title"] = "={{ $execution.workflow_name }}"
          workflow.update!(nodes: workflow.nodes)
          publish_workflow!(workflow)
          workflow.update!(name: "Draft workflow name")
        end

        it "uses the published workflow name in execution expressions" do
          expect(result[:form_data][:form_title]).to eq(workflow.published_version.name)
        end
      end
    end

    context "when form_description references $execution.resume_url" do
      before do
        trigger_node = workflow.nodes.find { |n| n["type"] == "trigger:form" }
        trigger_node["parameters"]["form_description"] = "={{ $execution.resume_url }}"
        workflow.update!(nodes: workflow.nodes)
        publish_workflow!(workflow)
      end

      it "resolves $execution.resume_url without materializing an execution" do
        expect(result).to run_successfully
        expect(result[:form_data][:form_description]).to eq("")
      end

      it "returns resume_token in the response" do
        expect(result).to run_successfully
        expect(result[:form_data][:resume_token]).to be_present
      end
    end

    context "when form_description references $execution.resumeFormUrl" do
      before do
        trigger_node = workflow.nodes.find { |n| n["type"] == "trigger:form" }
        trigger_node["parameters"]["form_description"] = "={{ $execution.resumeFormUrl }}"
        workflow.update!(nodes: workflow.nodes)
        publish_workflow!(workflow)
      end

      it "resolves $execution.resumeFormUrl without materializing an execution" do
        expect(result).to run_successfully
        expect(result[:form_data][:form_description]).to eq("")
      end
    end

    context "when a non-adjacent downstream form action exists" do
      before do
        extra =
          build_workflow_graph do |g|
            g.node "action-1", "action:send_message"
            g.node "form-action-1", "action:form", configuration: { "form_fields" => [] }
            g.chain "trigger-1", "action-1", "form-action-1"
          end
        workflow.update!(nodes: workflow.nodes + extra[:nodes], connections: extra[:connections])
        publish_workflow!(workflow)
      end

      it "detects the downstream form through intermediate nodes" do
        expect(result[:form_data][:has_downstream_form]).to be(true)
      end
    end

    context "with a waiting execution" do
      fab!(:waiting_workflow) do
        graph =
          build_workflow_graph do |g|
            g.node "trigger-1", "trigger:manual"
            g.node "form-action-1",
                   "action:form",
                   configuration: {
                     "form_title" => "Waiting Form",
                     "form_description" => "A waiting form",
                     "form_fields" => [
                       { "field_label" => "Feedback", "field_type" => "text", "required" => false },
                     ],
                   }
            g.chain "trigger-1", "form-action-1"
          end
        Fabricate(:discourse_workflows_workflow, published: true, **graph)
      end

      let(:resume_token) { SecureRandom.uuid }

      let!(:execution) do
        allow(MessageBus).to receive(:publish)
        exec = DiscourseWorkflows::Executor.new(waiting_workflow, "trigger-1", {}).run
        exec.update!(resume_token: resume_token)
        exec
      end

      let(:signature) do
        DiscourseWorkflows::WaitingExecution.resume_signature(
          execution_id: execution.id,
          resume_token: resume_token,
        )
      end
      let(:params) { { execution_id: execution.id, signature: signature } }

      it { is_expected.to run_successfully }

      it "builds waiting form data" do
        result
        form_data = result[:form_data]
        expect(form_data[:uuid]).to be_nil
        expect(form_data[:form_title]).to eq("Waiting Form")
        expect(form_data[:form_description]).to eq("A waiting form")
        expect(form_data[:form_fields]).to eq(
          [
            {
              "field_label" => "Feedback",
              "field_type" => "text",
              "required" => false,
              "key" => "feedback",
            },
          ],
        )
        expect(form_data[:response_mode]).to eq("on_received")
        expect(form_data[:has_downstream_form]).to be(false)
        expect(form_data).not_to have_key(:resume_token)
      end

      context "when the trigger captured query parameters" do
        before do
          execution.update!(trigger_data: { "formQueryParameters" => { "feedback" => "Prefill" } })
        end

        it "uses matching query parameters as waiting form field defaults" do
          expect(result[:form_data][:form_fields].first["default_value"]).to eq("Prefill")
        end
      end

      context "when form_description references $execution.resume_url" do
        fab!(:waiting_workflow) do
          graph =
            build_workflow_graph do |g|
              g.node "trigger-1", "trigger:manual"
              g.node "form-action-1",
                     "action:form",
                     configuration: {
                       "form_title" => "Waiting Form",
                       "form_description" => "={{ $execution.resume_url }}",
                       "form_fields" => [{ "field_label" => "Feedback", "field_type" => "text" }],
                     }
              g.chain "trigger-1", "form-action-1"
            end
          Fabricate(:discourse_workflows_workflow, published: true, **graph)
        end

        it "resolves $execution.resume_url from the execution context" do
          expect(result[:form_data][:form_description]).to eq(
            DiscourseWorkflows::WaitingExecution.webhook_url(
              execution_id: execution.id,
              resume_token: resume_token,
            ),
          )
        end
      end

      context "when form_description references $execution.resumeFormUrl" do
        fab!(:waiting_workflow) do
          graph =
            build_workflow_graph do |g|
              g.node "trigger-1", "trigger:manual"
              g.node "form-action-1",
                     "action:form",
                     configuration: {
                       "form_title" => "Waiting Form",
                       "form_description" => "={{ $execution.resumeFormUrl }}",
                       "form_fields" => [{ "field_label" => "Feedback", "field_type" => "text" }],
                     }
              g.chain "trigger-1", "form-action-1"
            end
          Fabricate(:discourse_workflows_workflow, published: true, **graph)
        end

        it "resolves $execution.resumeFormUrl from the execution context" do
          expect(result[:form_data][:form_description]).to eq(
            DiscourseWorkflows::WaitingExecution.form_waiting_url_for(
              execution_id: execution.id,
              resume_token: resume_token,
              absolute: true,
            ),
          )
        end
      end

      context "when context_data contains a conflicting __execution key" do
        fab!(:waiting_workflow) do
          graph =
            build_workflow_graph do |g|
              g.node "trigger-1", "trigger:manual"
              g.node "form-action-1",
                     "action:form",
                     configuration: {
                       "form_title" => "Waiting Form",
                       "form_description" => "=ID is {{ $execution.id }}",
                       "form_fields" => [{ "field_label" => "Feedback", "field_type" => "text" }],
                     }
              g.chain "trigger-1", "form-action-1"
            end
          Fabricate(:discourse_workflows_workflow, published: true, **graph)
        end

        before do
          ed = execution.execution_data || execution.build_execution_data
          ed.update!(
            data: {
              "entries" => ed.entries,
              "context" => {
                "__execution" => {
                  "id" => 9999,
                  "resume_url" => "https://malicious.example",
                },
              },
            }.to_json,
          )
        end

        it "uses the service-provided __execution over the stored context" do
          expect(result[:form_data][:form_description]).to eq("ID is #{execution.id}")
        end
      end

      context "when the draft workflow name changes after execution pauses" do
        fab!(:waiting_workflow) do
          graph =
            build_workflow_graph do |g|
              g.node "trigger-1", "trigger:manual"
              g.node "form-action-1",
                     "action:form",
                     configuration: {
                       "form_title" => "={{ $execution.workflow_name }}",
                       "form_fields" => [{ "field_label" => "Feedback", "field_type" => "text" }],
                     }
              g.chain "trigger-1", "form-action-1"
            end
          Fabricate(
            :discourse_workflows_workflow,
            name: "Published waiting workflow",
            published: true,
            **graph,
          )
        end

        before { waiting_workflow.update!(name: "Draft waiting workflow") }

        it "uses the execution snapshot workflow name" do
          expect(result[:form_data][:form_title]).to eq("Published waiting workflow")
        end
      end

      context "when form_description references a previous node's context" do
        fab!(:waiting_workflow) do
          graph =
            build_workflow_graph do |g|
              g.node "trigger-1", "trigger:manual", name: "Manual"
              g.node "form-action-1",
                     "action:form",
                     configuration: {
                       "form_title" => "Waiting Form",
                       "form_description" => '=Counter was {{ $("Manual").context["counter"] }}',
                       "form_fields" => [{ "field_label" => "Feedback", "field_type" => "text" }],
                     }
              g.chain "trigger-1", "form-action-1"
            end
          Fabricate(:discourse_workflows_workflow, published: true, **graph)
        end

        before do
          ed = execution.execution_data || execution.build_execution_data
          ed.update!(
            data: {
              "entries" => ed.entries,
              "context" => ed.context_data,
              "node_contexts" => {
                "trigger-1" => {
                  "counter" => 42,
                },
              },
            }.to_json,
          )
        end

        it "exposes node_contexts keyed by node name to the resolver" do
          expect(result[:form_data][:form_description]).to eq("Counter was 42")
        end

        context "when the workflow draft renames the node after execution pauses" do
          before do
            update_workflow_node(waiting_workflow, "trigger-1") { |node| node["name"] = "Renamed" }
          end

          it "uses the execution snapshot node name" do
            expect(result[:form_data][:form_description]).to eq("Counter was 42")
          end
        end
      end

      context "when a downstream form action exists" do
        fab!(:waiting_workflow) do
          graph =
            build_workflow_graph do |g|
              g.node "trigger-1", "trigger:manual"
              g.node "form-action-1",
                     "action:form",
                     configuration: {
                       "form_title" => "Waiting Form",
                       "form_description" => "A waiting form",
                       "form_fields" => [{ "field_label" => "Feedback", "field_type" => "text" }],
                     }
              g.node "form-action-2", "action:form", configuration: { "form_fields" => [] }
              g.chain "trigger-1", "form-action-1", "form-action-2"
            end
          Fabricate(:discourse_workflows_workflow, published: true, **graph)
        end

        it "sets has_downstream_form to true" do
          expect(result[:form_data][:has_downstream_form]).to be(true)
        end

        context "when the workflow is republished without the downstream form" do
          before do
            waiting_workflow.update!(
              nodes: waiting_workflow.nodes.reject { |node| node["id"] == "form-action-2" },
              connections:
                waiting_workflow.connections.reject do |connection|
                  connection["target_node_id"] == "form-action-2"
                end,
            )
            publish_workflow!(waiting_workflow)
          end

          it "uses the execution snapshot graph" do
            expect(result[:form_data][:has_downstream_form]).to be(true)
          end
        end
      end

      context "when a non-adjacent downstream form action exists" do
        fab!(:waiting_workflow) do
          graph =
            build_workflow_graph do |g|
              g.node "trigger-1", "trigger:manual"
              g.node "form-action-1",
                     "action:form",
                     configuration: {
                       "form_title" => "Waiting Form",
                       "form_description" => "A waiting form",
                       "form_fields" => [{ "field_label" => "Feedback", "field_type" => "text" }],
                     }
              g.node "action-between", "action:send_message"
              g.node "form-action-2", "action:form", configuration: { "form_fields" => [] }
              g.chain "trigger-1", "form-action-1", "action-between", "form-action-2"
            end
          Fabricate(:discourse_workflows_workflow, published: true, **graph)
        end

        it "detects the downstream form through intermediate nodes" do
          expect(result[:form_data][:has_downstream_form]).to be(true)
        end
      end

      context "when execution is not waiting" do
        before { execution.update!(status: :success) }

        it { is_expected.to fail_a_policy(:valid_waiting_request) }
      end

      context "when the waiting node is not a form action" do
        before { execution.update!(waiting_node_id: "trigger-1") }

        it { is_expected.to fail_a_policy(:action_form) }
      end
    end
  end
end
