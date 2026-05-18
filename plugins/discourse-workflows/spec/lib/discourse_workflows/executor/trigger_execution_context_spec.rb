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
  let(:ctx) do
    described_class.new(
      published_trigger:,
      node_type_class: DiscourseWorkflows::Nodes::Schedule::V1,
    )
  end

  describe "#get_timezone" do
    it "returns the resolved workflow timezone" do
      expect(ctx.get_timezone).to eq("Europe/Paris")
    end
  end
end
