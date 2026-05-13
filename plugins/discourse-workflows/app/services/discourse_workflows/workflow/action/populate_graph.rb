# frozen_string_literal: true

module DiscourseWorkflows
  class Workflow::Action::PopulateGraph < Service::ActionBase
    MAX_NODES = 50

    option :workflow
    option :nodes_data
    option :connections_data

    def call
      return false unless validate_nodes
      persist_graph(build_node_map)
    end

    private

    def build_node_map
      existing_nodes = workflow.nodes.index_by { |n| n["id"] }
      node_map = {}

      normalized_nodes_data.each_with_index do |node_data, index|
        client_id = node_data[:client_id].to_s
        existing = existing_nodes[client_id]
        node_map[client_id] = build_node_hash(node_data, client_id:, existing:, index:)
      end

      node_map
    end

    def build_node_hash(node_data, client_id:, existing:, index:)
      node_data = split_node_data(node_data, existing:)

      {
        "id" => existing ? existing["id"] : (client_id.presence || SecureRandom.uuid),
        "type" => node_data[:type],
        "type_version" => resolve_type_version(node_data, existing),
        "name" => node_data[:name],
        "position" => node_data[:position],
        "position_index" => index,
        "parameters" => node_data[:parameters],
        "credentials" => node_data[:credentials],
        "settings" => node_data[:settings],
        "webhook_id" => node_data[:webhook_id],
      }
    end

    def resolve_type_version(node_data, existing)
      existing&.dig("type_version") || node_data[:type_version] ||
        DiscourseWorkflows::Registry.latest_version(node_data[:type]) ||
        DiscourseWorkflows::Registry::DEFAULT_VERSION
    end

    def persist_graph(node_map)
      new_nodes = node_map.values
      new_connections = build_connections(node_map)
      workflow.update(nodes: new_nodes, connections: new_connections)
    end

    def validate_nodes
      validate_node_count
      return false if workflow.errors.any?

      existing_nodes_index = workflow.nodes.index_by { |n| n["id"] }

      normalized_nodes_data.each do |node_data|
        existing = existing_nodes_index[node_data[:client_id].to_s]
        type_version = resolve_type_version(node_data, existing)
        validate_node_type(node_data, type_version)
        validate_node_version(node_data, type_version)
      end

      workflow.errors.empty?
    end

    def validate_node_count
      if normalized_nodes_data.size > MAX_NODES
        workflow.errors.add(
          :base,
          I18n.t("discourse_workflows.errors.max_nodes_exceeded", max: MAX_NODES),
        )
      end
    end

    def validate_node_type(node_data, type_version)
      node_type_class =
        DiscourseWorkflows::Registry.find_node_type(node_data[:type], version: type_version)
      parameters = split_node_data(node_data, existing: nil)[:parameters]

      if node_type_class.respond_to?(:validate_configuration)
        node_type_class.validate_configuration(parameters, workflow.errors)
      end
    end

    def validate_node_version(node_data, type_version)
      if DiscourseWorkflows::Registry.available_versions(node_data[:type]).exclude?(type_version)
        workflow.errors.add(:base, "Unsupported version #{type_version} for #{node_data[:type]}")
      end
    end

    def build_connections(node_map)
      connections_data.filter_map do |connection_data|
        connection_data = connection_data.symbolize_keys
        source = node_map[connection_data[:source_client_id]]
        target = node_map[connection_data[:target_client_id]]
        next if source.nil? || target.nil?

        {
          "source_node_id" => source["id"],
          "target_node_id" => target["id"],
          "connection_type" => connection_data[:connection_type] || "main",
          "source_output_index" =>
            ConnectionIndex.from(connection_data, :source_output, :source_output_index),
          "target_input_index" =>
            ConnectionIndex.from(connection_data, :target_input, :target_input_index),
        }
      end
    end

    def normalized_nodes_data
      @normalized_nodes_data ||= nodes_data.map(&:symbolize_keys)
    end

    def split_node_data(node_data, existing:)
      split =
        NodeData.split(
          parameters: node_data[:parameters],
          credentials: node_data[:credentials],
          settings: node_data[:settings],
          webhook_id: resolved_webhook_id(node_data, existing: existing),
          node_type: node_data[:type],
        )

      node_data.merge(
        parameters: split["parameters"],
        credentials: split["credentials"],
        settings: split["settings"],
        webhook_id: split["webhook_id"],
      )
    end

    def resolved_webhook_id(node_data, existing:)
      return node_data[:webhook_id].presence if node_data[:webhook_id].present?
      return existing["webhook_id"] if existing&.dig("webhook_id").present?
      SecureRandom.uuid if node_data[:type] == "trigger:form"
    end
  end
end
