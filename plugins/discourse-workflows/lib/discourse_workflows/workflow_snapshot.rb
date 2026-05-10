# frozen_string_literal: true

module DiscourseWorkflows
  class WorkflowSnapshot
    SnapshotNode =
      Struct.new(:id, :type, :type_version, :name, :position, :configuration, keyword_init: true)

    SnapshotConnection =
      Struct.new(
        :source_node_id,
        :source_output_index,
        :target_node_id,
        :target_input_index,
        :connection_type,
        keyword_init: true,
      )

    attr_reader :nodes, :connections, :workflow_name

    def initialize(workflow_data)
      data = workflow_data.deep_stringify_keys
      @workflow_name = data["workflow_name"]
      @nodes_by_id = {}
      @nodes =
        data
          .fetch("nodes") { [] }
          .map do |n|
            node =
              SnapshotNode.new(
                id: n["id"].to_s,
                type: n["type"],
                type_version: n["type_version"] || Registry::DEFAULT_VERSION,
                name: n["name"],
                position: n["position"],
                configuration: n["configuration"] || {},
              ).freeze
            @nodes_by_id[node.id] = node
            node
          end

      used_target_indexes = Hash.new { |hash, key| hash[key] = Set.new }
      raw_connections = data.fetch("connections") { [] }
      raw_connections.each do |connection|
        next unless connection.key?("target_input_index")

        used_target_indexes[connection["target_node_id"].to_s] << connection[
          "target_input_index"
        ].to_i
      end

      @connections =
        data
          .fetch("connections") { [] }
          .map do |c|
            target_node_id = c["target_node_id"].to_s
            target_input_index =
              target_connection_index(c, target_node_id, used_target_indexes[target_node_id])
            used_target_indexes[target_node_id] << target_input_index
            SnapshotConnection.new(
              source_node_id: c["source_node_id"].to_s,
              source_output_index: ConnectionIndex.from(c, "source_output", "source_output_index"),
              target_node_id: target_node_id,
              target_input_index: target_input_index,
              connection_type: c["connection_type"] || "main",
            ).freeze
          end

      @connections_by_source = @connections.group_by(&:source_node_id)
      @connections_by_source_output_index =
        @connections.group_by do |connection|
          [connection.source_node_id, connection.source_output_index]
        end
      @connections_by_target = @connections.group_by(&:target_node_id)
    end

    def find_node(node_id)
      @nodes_by_id[node_id.to_s]
    end

    def connections_from_output_index(node, output_index)
      @connections_by_source_output_index.fetch([node.id, output_index.to_i]) { [] }
    end

    def connections_to(node)
      @connections_by_target.fetch(node.id) { [] }
    end

    def target_node(connection)
      @nodes_by_id[connection.target_node_id]
    end

    def node_has_reachable_downstream_of_type?(node_id, type)
      visited = Set.new
      queue = [node_id.to_s]

      while (current = queue.shift)
        next if visited.include?(current)
        visited << current

        @connections_by_source
          .fetch(current) { [] }
          .each do |connection|
            target_node = target_node(connection)
            next unless target_node
            return true if target_node.type == type

            queue << target_node.id
          end
      end

      false
    end

    def to_h
      result = {
        "nodes" =>
          nodes.map do |n|
            {
              "id" => n.id,
              "type" => n.type,
              "type_version" => n.type_version,
              "name" => n.name,
              "position" => n.position,
              "configuration" => n.configuration,
            }
          end,
        "connections" =>
          connections.map do |c|
            {
              "source_node_id" => c.source_node_id,
              "source_output_index" => c.source_output_index,
              "target_node_id" => c.target_node_id,
              "target_input_index" => c.target_input_index,
              "connection_type" => c.connection_type,
            }
          end,
      }
      result["workflow_name"] = workflow_name if workflow_name.present?
      result
    end

    def self.from_workflow(workflow, published: false)
      nodes = published ? workflow.published_nodes : workflow.nodes
      connections = published ? workflow.published_connections : workflow.connections
      workflow_name = published ? workflow.published_version&.name : workflow.draft_version&.name
      new(
        "nodes" => nodes,
        "connections" => connections,
        "workflow_name" => workflow_name || workflow.name,
      )
    end

    def self.from_version(workflow, version)
      new(
        "nodes" => version.nodes,
        "connections" => version.connections,
        "workflow_name" => version.name || workflow.name,
      )
    end

    def target_connection_index(connection, target_node_id, used_indexes)
      return connection["target_input_index"].to_i if connection.key?("target_input_index")

      target_node = @nodes_by_id[target_node_id]
      if target_node&.type == "flow:merge" &&
           target_node.configuration.fetch("mode") { "append" } == "append" &&
           connection["target_input"].to_s.in?(["", "main"])
        next_index = 0
        next_index += 1 while used_indexes.include?(next_index)
        return next_index
      end

      ConnectionIndex.legacy(connection["target_input"])
    end
  end
end
