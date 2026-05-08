# frozen_string_literal: true

module DiscourseWorkflows
  class Workflow::Update
    include Service::Base

    params do
      attribute :workflow_id, :integer
      attribute :name, :string
      attribute :error_workflow_id, :integer
      attribute :nodes
      attribute :connections

      before_validation { self.nodes = Array.wrap(nodes).select { it.is_a?(Hash) } if nodes }

      before_validation do
        self.connections = Array.wrap(connections).select { it.is_a?(Hash) } if connections
      end

      validates :workflow_id, presence: true
      validates :name, presence: true, length: { maximum: 100 }

      def updatable_attributes
        { name:, error_workflow_id: }
      end

      def graph_data_provided?
        !nodes.nil? || !connections.nil?
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
      workflow.assign_attributes(**params.updatable_attributes, updated_by: guardian.user)
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
      workflow.draft_version&.update(name: workflow.name, updated_by: guardian.user)
    end

    def expire_workflow_caches
      Site.clear_cache
      DiscourseWorkflows::WorkflowDependency.clear_cache!
    end
  end
end
