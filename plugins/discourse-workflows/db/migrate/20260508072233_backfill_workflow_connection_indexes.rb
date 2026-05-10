# frozen_string_literal: true

class BackfillWorkflowConnectionIndexes < ActiveRecord::Migration[8.0]
  TABLES = %i[discourse_workflows_workflows discourse_workflows_workflow_versions]

  def up
    TABLES.each { |table| backfill_table(table) }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def backfill_table(table)
    select_rows(table).each do |row|
      nodes = row["nodes"] || []
      connections = row["connections"] || []
      next unless nodes.is_a?(Array) && connections.is_a?(Array)

      updated_connections = indexed_connections(nodes, connections)
      updated_nodes = nodes_with_append_input_counts(nodes, updated_connections)
      next if updated_connections == connections && updated_nodes == nodes

      update_row(table, row["id"], updated_nodes, updated_connections)
    end
  end

  def select_rows(table)
    connection.select_all(<<~SQL)
      SELECT id, nodes, connections
      FROM #{table}
      WHERE jsonb_typeof(nodes) = 'array'
        AND jsonb_typeof(connections) = 'array'
    SQL
  end

  def update_row(table, id, nodes, connections)
    quoted_nodes = connection.quote(JSON.generate(nodes))
    quoted_connections = connection.quote(JSON.generate(connections))
    connection.execute(<<~SQL)
      UPDATE #{table}
      SET nodes = #{quoted_nodes}::jsonb,
          connections = #{quoted_connections}::jsonb
      WHERE id = #{id.to_i}
    SQL
  end

  def indexed_connections(nodes, connections)
    nodes_by_id = nodes.index_by { |node| node["id"].to_s }
    used_append_inputs = Hash.new { |hash, key| hash[key] = Set.new }

    connections.each_with_object([]) do |connection, result|
      target_node_id = connection["target_node_id"].to_s
      target_node = nodes_by_id[target_node_id]
      target_input_index = target_input_index(connection, target_node, used_append_inputs)
      used_append_inputs[target_node_id] << target_input_index if append_merge?(target_node)

      result << connection.except("source_output", "target_input").merge(
        "connection_type" => connection["connection_type"] || "main",
        "source_output_index" => source_output_index(connection),
        "target_input_index" => target_input_index,
      )
    end
  end

  def nodes_with_append_input_counts(nodes, connections)
    max_input_by_target =
      connections.each_with_object(Hash.new(-1)) do |connection, result|
        result[connection["target_node_id"].to_s] = [
          result[connection["target_node_id"].to_s],
          connection["target_input_index"].to_i,
        ].max
      end

    nodes.map do |node|
      next node unless append_merge?(node)

      count = [max_input_by_target[node["id"].to_s] + 1, 2].max
      node.merge("configuration" => (node["configuration"] || {}).merge("number_inputs" => count))
    end
  end

  def target_input_index(connection, target_node, used_append_inputs)
    return connection["target_input_index"].to_i if connection.key?("target_input_index")

    legacy_input = connection["target_input"].to_s
    if append_merge?(target_node) && legacy_input.in?(["", "main"])
      used = used_append_inputs[target_node["id"].to_s]
      index = 0
      index += 1 while used.include?(index)
      return index
    end

    legacy_connection_index(legacy_input)
  end

  def source_output_index(connection)
    return connection["source_output_index"].to_i if connection.key?("source_output_index")

    legacy_connection_index(connection["source_output"])
  end

  def append_merge?(node)
    node&.dig("type") == "flow:merge" && (node.dig("configuration", "mode") || "append") == "append"
  end

  def legacy_connection_index(value)
    value = value.to_s
    return 0 if value.blank? || value == "main" || value == "true" || value == "done"

    match = value.match(/\Ainput_(\d+)\z/)
    return match[1].to_i - 1 if match

    return 1 if %w[false loop].include?(value)

    value.to_i
  end
end
