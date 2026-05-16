# frozen_string_literal: true

module DiscourseWorkflows
  class Workflow::Update
    include Service::Base

    TIMEZONE_NOT_PROVIDED = Object.new.freeze

    params do
      attribute :workflow_id, :integer
      attribute :name, :string
      attribute :error_workflow_id, :integer
      attribute :timezone, default: -> { TIMEZONE_NOT_PROVIDED }
      attribute :nodes
      attribute :connections

      before_validation { self.nodes = Array.wrap(nodes).select { it.is_a?(Hash) } if nodes }

      before_validation do
        self.connections = Array.wrap(connections).select { it.is_a?(Hash) } if connections
      end

      validates :workflow_id, presence: true
      validates :name, presence: true, length: { maximum: 100 }
      validate :timezone_is_valid

      def updatable_attributes
        { name:, error_workflow_id: }
      end

      def timezone_provided?
        timezone != TIMEZONE_NOT_PROVIDED
      end

      def graph_data_provided?
        !nodes.nil? || !connections.nil?
      end

      def timezone_is_valid
        return if !timezone_provided? || timezone.blank?
        return if ScheduleRule.valid_timezone?(timezone)

        errors.add(:timezone, :invalid)
      end
    end

    policy :can_manage_workflows, class_name: Policy::CanManageWorkflows

    lock(:workflow_id) do
      model :workflow

      transaction do
        model :workflow, :update_workflow
        model :workflow, :save_workflow
        only_if(:graph_data_provided) do
          step :populate_graph
          model :draft_version, :create_draft_version
          step :assign_draft_version
          step :index_draft_dependencies
        end
        only_if(:metadata_only_update) do
          model :draft_version, :editable_draft_version
          step :assign_draft_version
          step :update_draft_version_metadata
          step :index_draft_dependencies
        end
      end
    end

    step :expire_workflow_caches

    private

    def fetch_workflow(params:)
      DiscourseWorkflows::Workflow.find_by(id: params.workflow_id)
    end

    def graph_data_provided(params:)
      params.graph_data_provided?
    end

    def update_workflow(workflow:, params:, guardian:)
      attrs = params.updatable_attributes
      attrs[:settings] = settings_with_timezone(workflow, params) if params.timezone_provided?
      workflow.assign_attributes(**attrs, updated_by: guardian.user)
      workflow
    end

    def save_workflow(workflow:)
      workflow.save
      workflow
    end

    def populate_graph(workflow:, params:)
      result =
        Workflow::Action::PopulateGraph.call(
          workflow:,
          nodes_data: params.nodes || [],
          connections_data: params.connections || [],
        )
      fail!(workflow.errors.full_messages) if result == false
    end

    def create_draft_version(workflow:, guardian:)
      workflow.create_draft_version!(user: guardian.user)
    end

    def assign_draft_version(workflow:, draft_version:)
      workflow.update!(draft_version:)
    end

    def index_draft_dependencies(workflow:, draft_version:)
      DiscourseWorkflows::WorkflowDependencyIndexer.call(workflow, version: draft_version)
    end

    def metadata_only_update(params:)
      !graph_data_provided(params:)
    end

    def editable_draft_version(workflow:, guardian:)
      workflow.editable_draft_version!(user: guardian.user)
    end

    def update_draft_version_metadata(workflow:, guardian:)
      workflow.draft_version&.update(
        name: workflow.name,
        settings: workflow.settings || {},
        updated_by: guardian.user,
      )
    end

    def settings_with_timezone(workflow, params)
      settings = (workflow.settings || {}).dup
      if params.timezone.present?
        settings["timezone"] = params.timezone
      else
        settings.delete("timezone")
      end
      settings
    end

    def expire_workflow_caches
      Site.clear_cache
      DiscourseWorkflows::WorkflowDependency.clear_cache!
    end
  end
end
