# frozen_string_literal: true

module Jobs
  module DiscourseWorkflows
    class ExecuteSecondsSchedule < ::Jobs::Base
      def execute(args)
        return unless SiteSetting.discourse_workflows_enabled

        workflow_id = args[:workflow_id]
        workflow_version_id = args[:workflow_version_id]
        node_id = args[:trigger_node_id]
        rule_index = args[:rule_index]
        token = args[:token]

        workflow =
          ::DiscourseWorkflows::Workflow.includes(:published_version).find_by(id: workflow_id)
        return if workflow.nil? || !workflow.published?
        return if workflow.published_version_id != workflow_version_id.to_i

        workflow_version = workflow.published_version
        unless ::DiscourseWorkflows::ScheduleRule.seconds_token_valid?(
                 workflow,
                 node_id,
                 rule_index,
                 token,
               )
          return
        end

        node = workflow_version.nodes.find { |n| n["id"] == node_id }
        return if node.nil?
        published_trigger =
          ::DiscourseWorkflows::PublishedTrigger.new(
            workflow: workflow,
            workflow_version: workflow_version,
            trigger_node: node,
          )

        rules =
          ::DiscourseWorkflows::ScheduleRule.rules_from_configuration(
            ::DiscourseWorkflows::NodeData.parameters(node),
          )
        rule = rules[rule_index]
        return if rule.nil? || !::DiscourseWorkflows::ScheduleRule.seconds_rule?(rule)

        now = Time.current.utc
        ::DiscourseWorkflows::ScheduleRule.mark_seconds_triggered!(
          workflow,
          node_id,
          rule_index,
          now,
        )

        ::DiscourseWorkflows::TriggerDispatcher.enqueue(
          published_trigger,
          trigger_data:
            ::DiscourseWorkflows::Nodes::Schedule::V1.new.output(
              time: now,
              timezone: ::DiscourseWorkflows::ScheduleRule.timezone_for(published_trigger),
            ),
        )

        interval = ::DiscourseWorkflows::ScheduleRule.seconds_interval(rule)
        Jobs.enqueue_at(
          ::DiscourseWorkflows::ScheduleRule.next_seconds_occurrence(now, interval),
          Jobs::DiscourseWorkflows::ExecuteSecondsSchedule,
          workflow_id: workflow_id,
          workflow_version_id: workflow_version_id,
          trigger_node_id: node_id,
          rule_index: rule_index,
          token: token,
        )
      end
    end
  end
end
