# frozen_string_literal: true

module DiscourseWorkflows
  class Workflow::ManualExecute
    include Service::Base

    params do
      attribute :workflow_id, :integer
      attribute :trigger_node_id, :string
      attribute :trigger_data, default: -> { {} }
      attribute :user_id, :integer

      validates :trigger_node_id, presence: true
    end

    policy :can_manage_workflows, class_name: Policy::CanManageWorkflows
    model :workflow
    model :trigger_node
    model :execution, :run_workflow

    private

    def fetch_workflow(params:)
      DiscourseWorkflows::Workflow.find_by(id: params.workflow_id)
    end

    def fetch_trigger_node(workflow:, params:)
      workflow.find_node(params.trigger_node_id)
    end

    def run_workflow(workflow:, trigger_node:, params:, guardian:)
      options =
        DiscourseWorkflows::Executor::ExecutionOptions.new(
          user: guardian.user,
          execution_mode: :manual,
          draft_execution: true,
        )
      DiscourseWorkflows::Executor.new(
        workflow,
        params.trigger_node_id,
        trigger_data(workflow:, trigger_node:, params:, user: guardian.user),
        options,
      ).run
    end

    def trigger_data(workflow:, trigger_node:, params:, user:)
      if params.trigger_data.blank? && trigger_node["type"] == "trigger:schedule"
        return TriggerRuntime.manual_trigger_data(workflow:, trigger_node:, user:)
      end

      return params.trigger_data unless trigger_node["type"] == "trigger:error"
      return params.trigger_data if params.trigger_data.present?

      DiscourseWorkflows::Nodes::Error::V1.manual_mock_data(workflow)
    end
  end
end
