# frozen_string_literal: true

module DiscourseWorkflows
  class TriggerRuntime
    class << self
      def tick!(now: Time.current.utc)
        now = scheduled_minute(now)

        published_triggers("trigger:schedule").each do |published_trigger|
          run_trigger(published_trigger, mode: :normal, activation_mode: :trigger, now:, tick: true)
        end
      end

      def activate_workflow!(workflow, workflow_version: workflow.published_version)
        return if workflow_version.nil?

        trigger_nodes(workflow_version).each do |node|
          published_trigger = PublishedTrigger.new(workflow:, workflow_version:, trigger_node: node)
          run_trigger(
            published_trigger,
            mode: :normal,
            activation_mode: :init,
            tick: false,
            dispatch: :none,
          )
        end
      end

      def deactivate_workflow!(_workflow)
      end

      def manual_trigger_data(workflow:, trigger_node:, user:)
        workflow_version = workflow.draft_version
        node_type_class = node_type_for(trigger_node)
        return {} unless trigger_node?(node_type_class)

        published_trigger =
          PublishedTrigger.new(workflow:, workflow_version:, trigger_node: trigger_node)
        ctx =
          Executor::TriggerExecutionContext.new(
            published_trigger:,
            node_type_class:,
            mode: :manual,
            activation_mode: :manual,
            dispatch: :collect,
            user:,
          )
        result = instantiate(node_type_class, trigger_node).trigger(ctx)
        result[:manual_trigger_function]&.call if result.is_a?(Hash)
        ctx.persist_static_data!
        ctx.emitted_trigger_data.first || {}
      end

      private

      def published_triggers(trigger_type)
        Workflow::Action::FindPublishedTriggers.call(trigger_type:)
      end

      def trigger_nodes(workflow_version)
        workflow_version.nodes.select { |node| trigger_node?(node_type_for(node)) }
      end

      def run_trigger(
        published_trigger,
        mode:,
        activation_mode:,
        now: Time.current.utc,
        tick: false,
        dispatch: :enqueue
      )
        node_type_class = node_type_for(published_trigger.trigger_node)
        return unless trigger_node?(node_type_class)

        published_trigger.workflow.with_lock do
          ctx =
            Executor::TriggerExecutionContext.new(
              published_trigger:,
              node_type_class:,
              mode:,
              activation_mode:,
              now:,
              tick:,
              dispatch:,
            )
          instantiate(node_type_class, published_trigger.trigger_node).trigger(ctx)
          ctx.persist_static_data!
        end
      end

      def node_type_for(node)
        Registry.find_node_type(node["type"], version: node["type_version"])
      end

      def trigger_node?(node_type_class)
        node_type_class &&
          node_type_class.instance_method(:trigger).owner != DiscourseWorkflows::NodeType
      end

      def instantiate(node_type_class, node)
        node_type_class.new(
          parameters: node["parameters"],
          credentials: node["credentials"],
          settings: node["settings"],
          webhook_id: node["webhook_id"],
        )
      end

      def scheduled_minute(time)
        time.utc.change(sec: 0, usec: 0)
      end
    end
  end
end
