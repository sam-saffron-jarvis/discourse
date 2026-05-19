# frozen_string_literal: true

module DiscourseWorkflows
  class Workflow < ActiveRecord::Base
    self.table_name = "discourse_workflows_workflows"

    PUBLISH_EVENT_ACTIVATED = "activated"
    PUBLISH_EVENT_DEACTIVATED = "deactivated"

    has_many :executions,
             class_name: "DiscourseWorkflows::Execution",
             foreign_key: "workflow_id",
             dependent: :destroy

    has_many :workflow_dependencies,
             class_name: "DiscourseWorkflows::WorkflowDependency",
             foreign_key: "workflow_id",
             dependent: :delete_all
    has_many :workflow_versions,
             class_name: "DiscourseWorkflows::WorkflowVersion",
             foreign_key: "workflow_id",
             dependent: :delete_all
    has_many :publish_history,
             -> { order(created_at: :desc) },
             class_name: "DiscourseWorkflows::WorkflowPublishHistory",
             foreign_key: "workflow_id",
             dependent: :delete_all

    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id"
    belongs_to :updated_by, class_name: "User", foreign_key: "updated_by_id", optional: true
    belongs_to :active_version,
               class_name: "DiscourseWorkflows::WorkflowVersion",
               foreign_key: "active_version_id",
               primary_key: "version_id",
               optional: true
    belongs_to :error_workflow,
               class_name: "DiscourseWorkflows::Workflow",
               foreign_key: "error_workflow_id",
               optional: true

    before_validation :assign_version_id, on: :create

    attribute :nodes, default: -> { [] }
    attribute :connections, default: -> { [] }
    attribute :static_data, default: -> { {} }
    attribute :settings, default: -> { {} }

    validates :name, presence: true, length: { maximum: 100 }
    validates :version_id, presence: true, length: { maximum: 36 }
    validate :error_workflow_must_exist

    before_destroy :nullify_error_workflow_back_references

    scope :published, -> { where.not(active_version_id: nil) }
    scope :filter_by_name,
          ->(name) do
            where("discourse_workflows_workflows.name ILIKE ?", "%#{sanitize_sql_like(name)}%")
          end
    scope :filter_by_trigger_type,
          ->(type) do
            where(
              "discourse_workflows_workflows.nodes @> ?",
              [{ "type" => "trigger:#{type}" }].to_json,
            )
          end

    def self.filtered(name: nil, trigger_type: nil, exclude_id: nil)
      scope = all
      scope = scope.filter_by_name(name) if name.present?
      scope = scope.filter_by_trigger_type(trigger_type) if trigger_type.present?
      scope = scope.where.not(id: exclude_id) if exclude_id
      scope
    end

    def find_node(node_id)
      find_node_in(nodes, node_id)
    end

    def find_published_node(node_id)
      find_node_in(published_nodes, node_id)
    end

    def published_nodes
      active_version&.nodes || []
    end

    def published_connections
      active_version&.connections || []
    end

    # Snapshots the current inline graph as a new immutable WorkflowVersion.
    # Bumps version_counter and stamps a fresh version_id on the row so the
    # row's identity matches the new snapshot's PK.
    def snapshot!(user:, autosaved: false, authors: nil)
      new_version_id = SecureRandom.uuid
      new_counter = version_counter.to_i + 1

      update!(version_id: new_version_id, version_counter: new_counter, updated_by: user)

      workflow_versions.create!(
        version_id: new_version_id,
        version_number: new_counter,
        name: name,
        nodes: nodes,
        connections: connections,
        settings: settings || {},
        static_data: static_data || {},
        autosaved: autosaved,
        authors: authors,
        created_by: user,
        updated_by: user,
      )
    end

    # Creates the very first snapshot, reusing the workflow's pre-assigned
    # version_id and version_counter. Used by Workflow::Create.
    def initial_snapshot!(user:, authors: nil)
      workflow_versions.create!(
        version_id: version_id,
        version_number: version_counter,
        name: name,
        nodes: nodes,
        connections: connections,
        settings: settings || {},
        static_data: static_data || {},
        autosaved: false,
        authors: authors,
        created_by: user,
        updated_by: user,
      )
    end

    def publish!(user: nil)
      published_node_ids = active_version_target&.nodes&.map { |n| n["id"].to_s } || []

      transaction do
        update!(
          active_version_id: version_id,
          static_data: (static_data || {}).slice(*published_node_ids),
        )
        publish_history.create!(
          version_id: version_id,
          event: PUBLISH_EVENT_ACTIVATED,
          user_id: user&.id,
        )
      end
    end

    def unpublish!(user: nil)
      previous_active_version_id = active_version_id

      transaction do
        update!(active_version_id: nil)
        publish_history.create!(
          version_id: previous_active_version_id,
          event: PUBLISH_EVENT_DEACTIVATED,
          user_id: user&.id,
        )
      end
    end

    def published?
      active_version_id.present?
    end

    def has_unpublished_changes?
      version_id != active_version_id
    end

    def find_node_in(node_collection, node_id)
      node_id_str = node_id.to_s
      node_collection.find { |n| n["id"] == node_id_str }
    end

    def trigger_node
      nodes.find { |n| n["type"]&.start_with?("trigger:") }
    end

    def node_static_data(node_id)
      static_data.fetch(node_id.to_s, {})
    end

    def update_node_static_data!(node_id, data)
      update!(static_data: static_data.merge(node_id.to_s => data))
    end

    def upstream_node_of(node_id)
      return if node_id.blank?
      node_id_str = node_id.to_s
      conn = connections.find { |c| c["target_node_id"] == node_id_str }
      return unless conn
      nodes.find { |n| n["id"] == conn["source_node_id"] }
    end

    def last_successful_execution
      executions.successful.includes(:execution_data).order(created_at: :desc).first
    end

    def node_has_reachable_downstream_of_type?(node_id, type, published: false)
      graph_nodes = published ? published_nodes : nodes
      graph_connections = published ? published_connections : connections
      node_by_id = graph_nodes.index_by { |n| n["id"] }
      visited = Set.new
      queue = [node_id.to_s]

      while (current = queue.shift)
        next if visited.include?(current)
        visited << current

        graph_connections
          .select { |c| c["source_node_id"] == current }
          .each do |conn|
            target_id = conn["target_node_id"]
            target_node = node_by_id[target_id]
            next unless target_node
            return true if target_node["type"] == type
            queue << target_id
          end
      end

      false
    end

    private

    def assign_version_id
      self.version_id ||= SecureRandom.uuid
    end

    # Returns the version that will become active after publish, i.e. the
    # snapshot for the row's current version_id, falling back to the existing
    # active version if the snapshot isn't loaded yet.
    def active_version_target
      workflow_versions.find_by(version_id: version_id) || active_version
    end

    def error_workflow_must_exist
      return if error_workflow_id.nil?
      errors.add(:error_workflow_id, :invalid) unless Workflow.exists?(error_workflow_id)
    end

    def nullify_error_workflow_back_references
      Workflow.where(error_workflow_id: id).update_all(
        error_workflow_id: nil,
        updated_at: Time.current,
      )
    end
  end
end

# == Schema Information
#
# Table name: discourse_workflows_workflows
#
#  id                :bigint           not null, primary key
#  active_version_id :string(36)
#  connections       :jsonb            not null
#  name              :string(100)      not null
#  nodes             :jsonb            not null
#  settings          :jsonb            not null
#  static_data       :jsonb            not null
#  version_counter   :integer          default(1), not null
#  version_id        :string(36)       not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  created_by_id     :integer          not null
#  error_workflow_id :bigint
#  updated_by_id     :integer
#
# Indexes
#
#  idx_workflows_nodes_gin                                   (nodes) USING gin
#  index_discourse_workflows_workflows_on_active_version_id  (active_version_id)
#  index_discourse_workflows_workflows_on_created_by_id      (created_by_id)
#  index_discourse_workflows_workflows_on_error_workflow_id  (error_workflow_id)
#  index_discourse_workflows_workflows_on_updated_by_id      (updated_by_id)
#  index_discourse_workflows_workflows_on_version_id         (version_id) UNIQUE
#
