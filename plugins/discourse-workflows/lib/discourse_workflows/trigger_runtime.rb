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

      def activate_workflow!(workflow, workflow_version: workflow.active_version)
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
        workflow_version = workflow.workflow_versions.find_by(version_id: workflow.version_id)
        node_type_class = node_type_for(trigger_node)
        return {} unless trigger_node?(node_type_class)

        published_trigger =
          PublishedTrigger.new(workflow:, workflow_version:, trigger_node: trigger_node)
        runtime_state = runtime_state_for(published_trigger)
        ctx =
          Executor::TriggerExecutionContext.new(
            published_trigger:,
            mode: :manual,
            activation_mode: :manual,
            dispatch: :collect,
            user:,
            runtime_state:,
          )
        result = instantiate(node_type_class, trigger_node).trigger(ctx)
        result[:manual_trigger_function]&.call if result.is_a?(Hash)
        commit_static_data!(published_trigger, runtime_state)
        runtime_state.collected_trigger_data.first || {}
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
          runtime_state = runtime_state_for(published_trigger, tick:)
          ctx =
            Executor::TriggerExecutionContext.new(
              published_trigger:,
              mode:,
              activation_mode:,
              now:,
              dispatch:,
              runtime_state:,
            )
          instantiate(node_type_class, published_trigger.trigger_node).trigger(ctx)
          commit_static_data!(published_trigger, runtime_state)
        end
      end

      def runtime_state_for(published_trigger, tick: false)
        Executor::TriggerExecutionContext::RuntimeState.new(
          static_data:
            published_trigger.workflow.node_static_data(published_trigger.trigger_node_id).deep_dup,
          tick:,
        )
      end

      def commit_static_data!(published_trigger, runtime_state)
        published_trigger.workflow.update_node_static_data!(
          published_trigger.trigger_node_id,
          runtime_state.static_data,
        )
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
