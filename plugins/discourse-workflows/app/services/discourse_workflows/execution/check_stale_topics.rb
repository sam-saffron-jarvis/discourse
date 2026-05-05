# frozen_string_literal: true

module DiscourseWorkflows
  class Execution::CheckStaleTopics
    include Service::Base

    MAX_TOPICS_PER_CYCLE = 100

    policy :workflows_enabled, class_name: DiscourseWorkflows::Policy::WorkflowsEnabled
    model :stale_trigger_nodes
    step :process_stale_trigger_nodes

    private

    def fetch_stale_trigger_nodes
      DiscourseWorkflows::WorkflowDependency.enabled_workflows_with_node_type("trigger:stale_topic")
    end

    def process_stale_trigger_nodes(stale_trigger_nodes:)
      stale_trigger_nodes.each do |workflow, node|
        newly_stale =
          DiscourseWorkflows::TriggerTracking.collect_stale_topics!(
            workflow,
            node,
            max_topics: MAX_TOPICS_PER_CYCLE,
          )

        newly_stale.each do |topic|
          trigger = DiscourseWorkflows::Nodes::StaleTopic::V1.new(topic)

          Jobs.enqueue(
            Jobs::DiscourseWorkflows::ExecuteWorkflow,
            workflow_id: workflow.id,
            trigger_node_id: node["id"],
            trigger_data: trigger.output,
          )
        end
      end
    end
  end
end
