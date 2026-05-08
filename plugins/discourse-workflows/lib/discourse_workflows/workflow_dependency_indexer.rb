# frozen_string_literal: true

module DiscourseWorkflows
  class WorkflowDependencyIndexer
    def self.call(workflow, version: workflow.draft_version)
      new(workflow, version:).call
    end

    def initialize(workflow, version:)
      @workflow = workflow
      @version = version
    end

    def call
      return unless @version

      rows = []

      @version.nodes.each do |node|
        node_id = node["id"]
        node_type = node["type"]
        config = node["configuration"] || {}

        rows << build_row("node_type", node_type, node_id) if node_type.present?

        if (cred_id = config["credential_id"]).present?
          rows << build_row("credential_id", cred_id, node_id)
        end

        if (dt_id = config["data_table_id"]).present?
          rows << build_row("data_table_id", dt_id, node_id)
        end

        if node_type == "trigger:webhook" && (path = config["path"]).present?
          rows << build_row("webhook_path", path, node_id)
        end
      end

      if @workflow.error_workflow_id.present?
        rows << build_row("error_workflow", @workflow.error_workflow_id, nil)
      end

      @workflow.with_lock do
        WorkflowDependency.where(workflow_version_id: @version.id).delete_all

        WorkflowDependency.insert_all(rows) if rows.present?
      end

      WorkflowDependency.clear_cache!
    end

    private

    def build_row(type, key, node_id)
      {
        workflow_id: @workflow.id,
        dependency_type: type,
        dependency_key: key.to_s,
        node_id: node_id,
        workflow_version_id: @version.id,
        created_at: Time.current,
      }
    end
  end
end
