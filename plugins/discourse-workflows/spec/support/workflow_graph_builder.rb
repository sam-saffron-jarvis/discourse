# frozen_string_literal: true

module DiscourseWorkflows
  class WorkflowGraphBuilder
    def initialize
      @nodes = []
      @connections = []
      @position_counter = 0
    end

    def node(
      id,
      type,
      name: nil,
      parameters: nil,
      credentials: {},
      settings: {},
      webhook_id: nil,
      configuration: {}
    )
      split =
        DiscourseWorkflows::NodeData.split(
          parameters: parameters || configuration,
          credentials: credentials,
          settings: settings,
          webhook_id: webhook_id,
          node_type: registered_node_type(type) || type,
        )

      @nodes << {
        "id" => id,
        "type" => type,
        "type_version" => "1.0",
        "name" => name || type.split(":").last.humanize,
        "position_index" => @position_counter,
        "parameters" => split["parameters"],
        "credentials" => split["credentials"],
        "settings" => split["settings"],
        "webhook_id" => split["webhook_id"],
      }
      @position_counter += 1
      self
    end

    def connect(source, target, output: "main", input: "main")
      @connections << {
        "source_node_id" => source,
        "target_node_id" => target,
        "source_output_index" => connection_index(output),
        "target_input_index" => connection_index(input),
      }
      self
    end

    def chain(*node_ids, output: "main")
      node_ids.each_cons(2) { |source, target| connect(source, target, output: output) }
      self
    end

    def to_h
      { nodes: @nodes, connections: @connections }
    end

    private

    def registered_node_type(type)
      DiscourseWorkflows::NodeType.registered_nodes.find { _1.description[:name] == type }
    end

    def connection_index(value)
      value = value.to_s
      return 0 if value.blank? || value == "main" || value == "true" || value == "done"

      match = value.match(/\Ainput_(\d+)\z/)
      return match[1].to_i - 1 if match

      return 1 if %w[false loop].include?(value)

      value.to_i
    end
  end
end

def build_workflow_graph
  builder = DiscourseWorkflows::WorkflowGraphBuilder.new
  yield builder
  builder.to_h
end

def workflow_nodes_with_update(workflow, node_id)
  workflow.nodes.map do |workflow_node|
    node = workflow_node.deep_dup
    next node unless node["id"] == node_id

    updated_node = yield node
    updated_node.is_a?(Hash) ? updated_node : node
  end
end

def update_workflow_node(workflow, node_id, &block)
  workflow.update!(nodes: workflow_nodes_with_update(workflow, node_id, &block))
end

def publish_workflow!(workflow)
  version = workflow.snapshot!(user: workflow.created_by)
  workflow.update!(active_version_id: workflow.version_id)
  DiscourseWorkflows::WorkflowDependencyIndexer.call(workflow, version:)
  workflow.reload
end

def unpublish_workflow!(workflow)
  workflow.update!(active_version_id: nil)
end
