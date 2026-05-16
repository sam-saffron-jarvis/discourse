# frozen_string_literal: true

module DiscourseWorkflows
  class Workflow < ActiveRecord::Base
    self.table_name = "discourse_workflows_workflows"
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

    belongs_to :created_by, class_name: "User", foreign_key: "created_by_id"
    belongs_to :updated_by, class_name: "User", foreign_key: "updated_by_id", optional: true
    belongs_to :draft_version,
               class_name: "DiscourseWorkflows::WorkflowVersion",
               foreign_key: "draft_version_id",
               optional: true
    belongs_to :published_version,
               class_name: "DiscourseWorkflows::WorkflowVersion",
               foreign_key: "published_version_id",
               optional: true
    belongs_to :error_workflow,
               class_name: "DiscourseWorkflows::Workflow",
               foreign_key: "error_workflow_id",
               optional: true

    attribute :nodes, default: -> { [] }
    attribute :connections, default: -> { [] }
    attribute :static_data, default: -> { {} }

    validates :name, presence: true, length: { maximum: 100 }
    validate :error_workflow_must_exist

    scope :published, -> { where.not(published_version_id: nil) }
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
      published_version&.nodes || []
    end

    def published_connections
      published_version&.connections || []
    end

    def next_version_number
      workflow_versions.maximum(:version_number).to_i + 1
    end

    def create_draft_version!(user:)
      workflow_versions.create!(
        version_number: next_version_number,
        name: name,
        nodes: nodes,
        connections: connections,
        settings: settings || {},
        static_data: static_data || {},
        created_by: user,
        updated_by: user,
      )
    end

    def editable_draft_version!(user:)
      return if draft_version.blank?
      return draft_version if draft_version_id != published_version_id

      copy_version_to_draft!(draft_version, user:)
    end

    def publish_draft_version!
      draft_node_ids = draft_version.nodes.map { |node| node["id"].to_s }
      update!(
        published_version: draft_version,
        static_data: (static_data || {}).slice(*draft_node_ids),
      )
    end

    def unpublish!
      update!(published_version: nil)
    end

    def published?
      published_version_id.present?
    end

    def has_unpublished_changes?
      draft_version_id != published_version_id
    end

    def find_node_in(node_collection, node_id)
      node_id_str = node_id.to_s
      node_collection.find { |n| n["id"] == node_id_str }
    end

    def copy_version_to_draft!(source_version, user:)
      workflow_versions.create!(
        version_number: next_version_number,
        name: name,
        nodes: source_version.nodes,
        connections: source_version.connections,
        settings: source_version.settings || {},
        static_data: source_version.static_data || {},
        created_by: user,
        updated_by: user,
      )
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

    def each_seconds_schedule_rule(published: false)
      schedule_nodes = published ? published_nodes : nodes

      schedule_nodes.each do |node|
        next unless node["type"] == "trigger:schedule"

        rules =
          ScheduleRule.rules_from_configuration(NodeData.parameters(node)).first(
            ScheduleRule::MAX_RULES_PER_NODE,
          )
        rules.each_with_index do |rule, rule_index|
          next unless ScheduleRule.seconds_rule?(rule)
          yield node, rule, rule_index
        end
      end
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

    def self.form_field_key(field)
      field["field_name"].presence || field["field_label"].to_s.parameterize(separator: "_")
    end

    def self.resolve_field_keys(fields)
      fields.map { |f| f.merge("key" => form_field_key(f)) }
    end

    private

    def error_workflow_must_exist
      return if error_workflow_id.nil?
      if error_workflow_id == id || !Workflow.exists?(error_workflow_id)
        errors.add(:error_workflow_id, :invalid)
      end
    end
  end
end

# == Schema Information
#
# Table name: discourse_workflows_workflows
#
#  id                   :bigint           not null, primary key
#  connections          :jsonb
#  name                 :string           not null
#  nodes                :jsonb
#  settings             :jsonb
#  static_data          :jsonb
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  created_by_id        :integer          not null
#  draft_version_id     :bigint
#  error_workflow_id    :bigint
#  published_version_id :bigint
#  updated_by_id        :integer
#
# Indexes
#
#  idx_workflows_nodes_gin                                      (nodes) USING gin
#  index_discourse_workflows_workflows_on_created_by_id         (created_by_id)
#  index_discourse_workflows_workflows_on_draft_version_id      (draft_version_id)
#  index_discourse_workflows_workflows_on_error_workflow_id     (error_workflow_id)
#  index_discourse_workflows_workflows_on_published_version_id  (published_version_id)
#  index_discourse_workflows_workflows_on_updated_by_id         (updated_by_id)
#
