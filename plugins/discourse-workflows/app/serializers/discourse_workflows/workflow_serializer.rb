# frozen_string_literal: true

module DiscourseWorkflows
  class WorkflowSerializer < ApplicationSerializer
    attributes :id,
               :name,
               :nodes,
               :connections,
               :draft_version_id,
               :published_version_id,
               :has_unpublished_changes,
               :error_workflow_id,
               :error_workflow_name,
               :timezone,
               :created_at,
               :updated_at,
               :last_execution_status,
               :last_execution_at,
               :last_execution_node_outputs

    attribute :created_by
    attribute :updated_by

    def nodes
      (object.nodes || []).sort_by { |n| n["position_index"] || 0 }
    end

    def connections
      object.connections || []
    end

    def has_unpublished_changes
      object.has_unpublished_changes?
    end

    def created_by
      BasicUserSerializer.new(object.created_by, root: false).as_json
    end

    def updated_by
      return if object.updated_by.blank?
      BasicUserSerializer.new(object.updated_by, root: false).as_json
    end

    def error_workflow_name
      object.error_workflow&.name
    end

    def timezone
      object.settings&.dig("timezone") || DiscourseWorkflows::ScheduleRule.default_timezone
    end

    def include_error_workflow_name?
      object.error_workflow_id.present?
    end

    def last_execution_at
      return unless object.attributes.key?("last_execution_at")
      object.attributes["last_execution_at"]
    end

    def last_execution_status
      return unless object.attributes.key?("last_execution_status_value")
      DiscourseWorkflows::Execution.statuses.key(object.attributes["last_execution_status_value"])
    end

    def include_last_execution_node_outputs?
      !object.attributes.key?("last_execution_status_value")
    end

    def last_execution_node_outputs
      execution =
        object
          .executions
          .includes(:execution_data)
          .where(status: :success)
          .order(created_at: :desc)
          .first
      return unless execution&.execution_data

      entries = execution.execution_data.entries || {}
      entries.each_with_object({}) do |(node_id, steps), outputs|
        step = Array(steps).find { |s| s["status"] == "success" }
        first_json = (step["output"] || []).dig(0, "json") if step
        outputs[node_id] = first_json if first_json.present?
      end
    end
  end
end
