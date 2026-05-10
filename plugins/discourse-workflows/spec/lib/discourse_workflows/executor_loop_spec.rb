# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Executor do
  fab!(:user)

  before { SiteSetting.tagging_enabled = true }

  describe "#run" do
    it "executes a loop workflow: trigger -> loop -> action -> loop-back -> done" do
      graph =
        build_workflow_graph do |g|
          g.node "trigger-1", "trigger:manual"
          g.node "set-fields-1",
                 "action:set_fields",
                 configuration: {
                   "mode" => "json",
                   "include_input" => false,
                   "json" => '{"item_id": "1"}',
                 }
          g.node "loop-1", "flow:loop_over_items", configuration: { "batch_size" => 1 }
          g.node "process-1",
                 "action:set_fields",
                 configuration: {
                   "mode" => "json",
                   "include_input" => true,
                   "json" => '{"processed": "true"}',
                 }
          g.node "done-1",
                 "action:set_fields",
                 name: "Final Step",
                 configuration: {
                   "mode" => "json",
                   "include_input" => true,
                   "json" => '{"completed": "true"}',
                 }
          g.chain "trigger-1", "set-fields-1", "loop-1"
          g.connect "loop-1", "process-1", output: "loop"
          g.chain "process-1", "loop-1"
          g.connect "loop-1", "done-1", output: "done"
        end
      workflow =
        Fabricate(:discourse_workflows_workflow, created_by: user, published: true, **graph)

      trigger_data = {}
      execution = described_class.new(workflow, "trigger-1", trigger_data).run

      expect(execution.status).to eq("success")

      final_output = execution.execution_data.context_data["Final Step"]
      expect(final_output).to be_an(Array)
      expect(final_output.first["json"]).to include("processed" => "true", "completed" => "true")
    end

    it "processes multiple items through the loop in batches" do
      graph =
        build_workflow_graph do |g|
          g.node "trigger-1", "trigger:manual"
          g.node "loop-1", "flow:loop_over_items", configuration: { "batch_size" => 1 }
          g.node "process-1",
                 "action:set_fields",
                 configuration: {
                   "mode" => "json",
                   "include_input" => true,
                   "json" => '{"tagged": "yes"}',
                 }
          g.node "done-1",
                 "action:set_fields",
                 name: "Done",
                 configuration: {
                   "include_input" => true,
                   "fields" => [{ "key" => "final", "value" => "true", "type" => "string" }],
                 }
          g.chain "trigger-1", "loop-1"
          g.connect "loop-1", "process-1", output: "loop"
          g.chain "process-1", "loop-1"
          g.connect "loop-1", "done-1", output: "done"
        end
      workflow =
        Fabricate(:discourse_workflows_workflow, created_by: user, published: true, **graph)

      trigger_data = { items: [{ name: "a" }, { name: "b" }, { name: "c" }] }
      execution = described_class.new(workflow, "trigger-1", trigger_data).run

      expect(execution.status).to eq("success")

      done_output = execution.execution_data.context_data["Done"]
      expect(done_output).to be_an(Array)
      expect(done_output.length).to eq(1)
    end

    it "waits for required target inputs before executing a merge node" do
      graph =
        build_workflow_graph do |g|
          g.node "trigger-1", "trigger:manual"
          g.node "left-1",
                 "action:set_fields",
                 configuration: {
                   "mode" => "json",
                   "include_input" => false,
                   "json" => '{"id": 1, "left": "yes"}',
                 }
          g.node "right-1",
                 "action:set_fields",
                 configuration: {
                   "mode" => "json",
                   "include_input" => false,
                   "json" => '{"topic_id": 1, "right": "yes"}',
                 }
          g.node "merge-1",
                 "flow:merge",
                 name: "Merge branches",
                 configuration: {
                   "mode" => "combine",
                   "combine_by" => "matching_fields",
                   "fields_to_match" => [{ "field_1" => "id", "field_2" => "topic_id" }],
                 }
          g.connect "trigger-1", "left-1"
          g.connect "trigger-1", "right-1"
          g.connect "left-1", "merge-1", input: "input_1"
          g.connect "right-1", "merge-1", input: "input_2"
        end
      workflow =
        Fabricate(:discourse_workflows_workflow, created_by: user, published: true, **graph)

      execution = described_class.new(workflow, "trigger-1", {}).run

      expect(execution.status).to eq("success")
      merge_steps =
        execution.execution_data.steps_array.select { |step| step["node_id"] == "merge-1" }
      expect(merge_steps.length).to eq(1)
      expect(merge_steps.first["output"].first["json"]).to include(
        "id" => 1,
        "left" => "yes",
        "topic_id" => 1,
        "right" => "yes",
      )
    end

    it "waits for all incoming branches before executing append merge" do
      graph =
        build_workflow_graph do |g|
          g.node "trigger-1", "trigger:manual"
          g.node "first-1",
                 "action:set_fields",
                 configuration: {
                   "mode" => "json",
                   "include_input" => false,
                   "json" => '{"source": "first"}',
                 }
          g.node "second-1",
                 "action:set_fields",
                 configuration: {
                   "mode" => "json",
                   "include_input" => false,
                   "json" => '{"source": "second"}',
                 }
          g.node "third-1",
                 "action:set_fields",
                 configuration: {
                   "mode" => "json",
                   "include_input" => false,
                   "json" => '{"source": "third"}',
                 }
          g.node "merge-1",
                 "flow:merge",
                 name: "Append branches",
                 configuration: {
                   "mode" => "append",
                 }
          g.connect "trigger-1", "first-1"
          g.connect "trigger-1", "second-1"
          g.connect "trigger-1", "third-1"
          g.connect "first-1", "merge-1"
          g.connect "second-1", "merge-1"
          g.connect "third-1", "merge-1"
        end
      workflow =
        Fabricate(:discourse_workflows_workflow, created_by: user, published: true, **graph)

      execution = described_class.new(workflow, "trigger-1", {}).run

      expect(execution.status).to eq("success")
      merge_steps =
        execution.execution_data.steps_array.select { |step| step["node_id"] == "merge-1" }
      expect(merge_steps.length).to eq(1)
      expect(merge_steps.first["output"].map { |item| item["json"]["source"] }).to contain_exactly(
        "first",
        "second",
        "third",
      )
    end

    it "does not wait for unwired append merge inputs" do
      graph =
        build_workflow_graph do |g|
          g.node "trigger-1", "trigger:manual"
          g.node "first-1",
                 "action:set_fields",
                 configuration: {
                   "mode" => "json",
                   "include_input" => false,
                   "json" => '{"source": "first"}',
                 }
          g.node "second-1",
                 "action:set_fields",
                 configuration: {
                   "mode" => "json",
                   "include_input" => false,
                   "json" => '{"source": "second"}',
                 }
          g.node "merge-1",
                 "flow:merge",
                 name: "Append branches",
                 configuration: {
                   "mode" => "append",
                   "number_inputs" => 3,
                 }
          g.connect "trigger-1", "first-1"
          g.connect "trigger-1", "second-1"
          g.connect "first-1", "merge-1", input: "input_1"
          g.connect "second-1", "merge-1", input: "input_2"
        end
      workflow =
        Fabricate(:discourse_workflows_workflow, created_by: user, published: true, **graph)

      execution = described_class.new(workflow, "trigger-1", {}).run

      expect(execution.status).to eq("success")
      merge_steps =
        execution.execution_data.steps_array.select { |step| step["node_id"] == "merge-1" }
      expect(merge_steps.length).to eq(1)
      expect(merge_steps.first["output"].map { |item| item["json"]["source"] }).to contain_exactly(
        "first",
        "second",
      )
    end
  end
end
