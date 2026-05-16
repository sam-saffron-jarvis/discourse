# frozen_string_literal: true

module DiscourseWorkflows
  class Executor
    class ErrorWorkflowTrigger
      def initialize(workflow, steps, execution: nil, execution_mode:)
        @workflow = workflow
        @steps = steps
        @execution = execution
        @execution_mode = execution_mode
      end

      def trigger_error_workflow(error)
        return if @execution_mode == :manual

        error_workflow = error_workflow_for_failure
        return unless eligible?(error_workflow)
        return if self_retriggering?(error_workflow)

        workflow_version = error_workflow.published_version
        trigger_node = trigger_node_for(workflow_version)
        unless trigger_node
          Rails.logger.warn(
            "discourse-workflows: error workflow #{error_workflow.id} has no trigger:error node, skipping error handling",
          )
          return
        end

        Jobs.enqueue(
          Jobs::DiscourseWorkflows::ExecuteWorkflow,
          workflow_id: error_workflow.id,
          workflow_version_id: workflow_version.id,
          trigger_node_id: trigger_node["id"],
          trigger_data: build_error_data(error),
          execution_mode: "error_mode",
        )
      end

      private

      def error_workflow_for_failure
        return @workflow.error_workflow if @workflow.error_workflow_id.present?
        @workflow if trigger_node_for(@workflow.published_version)
      end

      def eligible?(error_workflow)
        error_workflow&.published?
      end

      def self_retriggering?(error_workflow)
        @execution_mode == :error_mode && error_workflow.id == @workflow.id
      end

      def trigger_node_for(workflow_version)
        workflow_version&.nodes&.find { |n| n["type"] == "trigger:error" }
      end

      def build_error_data(error)
        data = { "workflow" => { "id" => @workflow.id.to_s, "name" => @workflow.name } }

        if @execution
          data["execution"] = {
            "id" => @execution.id.to_s,
            "url" => execution_url,
            "retryOf" => nil,
            "error" => serialized_error(error),
            "lastNodeExecuted" => last_failed_step_node_name,
            "mode" => n8n_execution_mode,
          }
        else
          data["trigger"] = { "error" => serialized_error(error), "mode" => n8n_execution_mode }
        end

        data
      end

      def execution_url
        "#{Discourse.base_url}/admin/plugins/discourse-workflows/workflows/" \
          "#{@workflow.id}/executions/#{@execution.id}"
      end

      def serialized_error(error)
        serialized = { "message" => error.message.to_s.truncate(1000), "name" => error.class.name }

        stack = Array(error.backtrace).first(50).join("\n")
        serialized["stack"] = stack.truncate(10_000) if stack.present?

        serialized
      end

      def n8n_execution_mode
        return "error" if @execution_mode == :error_mode
        return "manual" if @execution_mode == :manual
        return "webhook" if webhook_trigger?

        "trigger"
      end

      def webhook_trigger?
        %w[trigger:form trigger:webhook].include?(trigger_node_type)
      end

      def trigger_node_type
        @trigger_node_type ||=
          begin
            trigger_node = @execution&.workflow_node(@execution.trigger_node_id)
            trigger_node&.dig("type")
          end
      end

      def last_failed_step_node_name
        step =
          @steps.reverse_each.find do |s|
            s.respond_to?(:error?) ? s.error? : s["status"] == "error"
          end
        return step.node_name if step.respond_to?(:node_name)

        step&.dig("node_name")
      end
    end
  end
end
