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
      DiscourseWorkflows::Workflow::Action::FindPublishedTriggers.call(
        trigger_type: "trigger:stale_topic",
      )
    end

    def process_stale_trigger_nodes(stale_trigger_nodes:)
      stale_trigger_nodes.each do |published_trigger|
        newly_stale =
          DiscourseWorkflows::TriggerTracking.collect_stale_topics!(
            published_trigger.workflow,
            published_trigger.trigger_node,
            max_topics: MAX_TOPICS_PER_CYCLE,
          )

        newly_stale.each do |topic|
          trigger = DiscourseWorkflows::Nodes::StaleTopic::V1.new(topic)

          DiscourseWorkflows::TriggerDispatcher.enqueue(
            published_trigger,
            trigger_data: trigger.output,
          )
        end
      end
    end
  end
end
