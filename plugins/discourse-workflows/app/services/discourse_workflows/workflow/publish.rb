# frozen_string_literal: true

module DiscourseWorkflows
  class Workflow::Publish
    include Service::Base

    params do
      attribute :workflow_id, :integer

      validates :workflow_id, presence: true
    end

    policy :can_manage_workflows, class_name: Policy::CanManageWorkflows

    lock(:workflow_id) do
      model :workflow

      transaction do
        model :draft_version
        step :publish_draft_version
      end
    end

    step :expire_workflow_caches
    step :activate_triggers

    private

    def fetch_workflow(params:)
      DiscourseWorkflows::Workflow.find_by(id: params.workflow_id)
    end

    def fetch_draft_version(workflow:)
      workflow.draft_version
    end

    def publish_draft_version(workflow:)
      workflow.publish_draft_version!
    end

    def expire_workflow_caches
      Site.clear_cache
      DiscourseWorkflows::WorkflowDependency.clear_cache!
    end

    def activate_triggers(workflow:, draft_version:)
      TriggerRuntime.activate_workflow!(workflow, workflow_version: draft_version)
    end
  end
end
