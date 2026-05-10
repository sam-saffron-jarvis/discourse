# frozen_string_literal: true

module DiscourseWorkflows
  class WorkflowDependency < ActiveRecord::Base
    self.table_name = "discourse_workflows_workflow_dependencies"

    TOPIC_ADMIN_BUTTON_CACHE_KEY = "topic_admin_buttons"

    belongs_to :workflow, class_name: "DiscourseWorkflows::Workflow"
    belongs_to :workflow_version, class_name: "DiscourseWorkflows::WorkflowVersion", optional: true

    TYPES = %w[
      credential_id
      data_table_id
      node_type
      webhook_path
      workflow_call
      error_workflow
    ].freeze

    validates :dependency_type, inclusion: { in: TYPES }

    scope :of_type, ->(type) { where(dependency_type: type) }

    def self.cache
      @cache ||= DistributedCache.new("discourse_workflows_dependencies")
    end

    def self.clear_cache!
      cache.clear
    end

    def self.cached_topic_admin_buttons
      cache.defer_get_set(CACHE_KEY) do
        Workflow::Action::FindPublishedTriggers
          .call(trigger_type: "trigger:topic_admin_button")
          .map do |published_trigger|
            {
              trigger_node_id: published_trigger.trigger_node_id,
              workflow_id: published_trigger.workflow_id,
              label: published_trigger.trigger_node.dig("configuration", "label"),
              icon: published_trigger.trigger_node.dig("configuration", "icon"),
            }
          end
      end
    end

    def self.workflows_referencing(type, key)
      joins(:workflow)
        .where(dependency_type: type, dependency_key: key.to_s)
        .where(
          "discourse_workflows_workflow_dependencies.workflow_version_id IN " \
            "(discourse_workflows_workflows.draft_version_id, " \
            "discourse_workflows_workflows.published_version_id)",
        )
        .select(:workflow_id)
    end
  end
end

# == Schema Information
#
# Table name: discourse_workflows_workflow_dependencies
#
#  id                   :bigint           not null, primary key
#  dependency_key       :string(500)      not null
#  dependency_type      :string(50)       not null
#  created_at           :datetime         not null
#  node_id              :string(100)
#  published_version_id :bigint
#  workflow_id          :bigint           not null
#  workflow_version_id  :bigint
#
# Indexes
#
#  idx_dwf_deps_published_version_id                               (published_version_id)
#  idx_dwf_deps_workflow_version_id                                (workflow_version_id)
#  idx_workflow_deps_type_key                                      (dependency_type,dependency_key)
#  index_discourse_workflows_workflow_dependencies_on_workflow_id  (workflow_id)
#
