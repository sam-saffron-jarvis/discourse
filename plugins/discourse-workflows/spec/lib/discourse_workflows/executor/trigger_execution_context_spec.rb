# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Executor::TriggerExecutionContext do
  fab!(:workflow) do
    graph =
      build_workflow_graph do |g|
        g.node "trigger-1",
               "trigger:schedule",
               configuration: {
                 rule: {
                   interval: [{ field: "days" }],
                 },
               }
      end
    Fabricate(
      :discourse_workflows_workflow,
      published: true,
      settings: {
        "timezone" => "Europe/Paris",
      },
      **graph,
    )
  end

  let(:trigger_node) { workflow.published_version.nodes.first }
  let(:published_trigger) do
    DiscourseWorkflows::PublishedTrigger.new(
      workflow:,
      workflow_version: workflow.published_version,
      trigger_node:,
    )
  end
  let(:runtime_state) do
    described_class::RuntimeState.new(
      static_data: workflow.node_static_data(trigger_node["id"]).deep_dup,
    )
  end
  let(:ctx) { described_class.new(published_trigger:, runtime_state:) }

  describe "#get_timezone" do
    it "returns the resolved workflow timezone" do
      expect(ctx.get_timezone).to eq("Europe/Paris")
    end
  end
end
