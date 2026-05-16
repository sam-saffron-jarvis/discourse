# frozen_string_literal: true

module DiscourseWorkflows
  class NodeOutputProxy
    BLOCKED_NODE_NAMES = %w[constructor prototype eval].freeze
    MISSING_ITEM_LINK_MESSAGE = "Info for expression missing from previous node"
    MULTIPLE_MATCHING_ITEMS_MESSAGE = "Multiple matching items for expression"

    def initialize(context)
      @context = context || {}
    end

    def item(name, item_index: nil)
      name_str = name.to_s
      return { "json" => {} } if blocked_node_name?(name_str)

      linked_item_for_expression(name_str, item_index: item_index_for(item_index))
    end

    def all(name, branch_index: nil, run_index: nil)
      name_str = name.to_s
      return [] if blocked_node_name?(name_str)

      branch_index = default_branch_index_for(name_str) if branch_index.nil?
      node_items_for_expression(name_str, branch_index:, run_index:)
    end

    def first(name, branch_index: nil, run_index: nil)
      all(name, branch_index:, run_index:).first || { "json" => {} }
    end

    def last(name, branch_index: nil, run_index: nil)
      items = all(name, branch_index:, run_index:)
      items[items.length - 1] || { "json" => {} }
    end

    def context(name)
      @context.dig("__node_contexts", name.to_s) || {}
    end

    def params(name)
      @context.dig("__node_parameters_by_name", name.to_s) || {}
    end

    def executed?(name)
      name_str = name.to_s
      return false if blocked_node_name?(name_str)

      node_id = node_id_for_expression_name(name_str)
      return Array(@context.dig("__node_runs", node_id.to_s)).present? if node_id

      @context.key?(name_str)
    end

    private

    def blocked_node_name?(name)
      name.start_with?("_") || BLOCKED_NODE_NAMES.include?(name)
    end

    def item_index_for(item_index)
      return item_index.to_i unless item_index.nil?

      @context.fetch("$itemIndex") { 0 }.to_i
    end

    def linked_item_for_expression(name, item_index:)
      target_node_id = node_id_for_expression_name(name)
      target_items = node_items_for_expression(name)
      return { "json" => {} } if target_items.blank?

      unless target_node_id && @context["__current_node_id"] && @context["__node_runs"]
        raise MISSING_ITEM_LINK_MESSAGE
      end

      input_source = current_input_source
      raise MISSING_ITEM_LINK_MESSAGE if input_source.blank?

      matches =
        trace_linked_items(
          input_source["node_id"],
          input_source["output_index"].to_i,
          item_index,
          target_node_id,
          Set.new,
        )

      raise MISSING_ITEM_LINK_MESSAGE if matches.blank?

      distinct_matches =
        matches.uniq { |match| [match[:node_id], match[:output_index], match[:item_index]] }
      raise MULTIPLE_MATCHING_ITEMS_MESSAGE if distinct_matches.length > 1

      distinct_matches.first[:item]
    end

    def node_items_for_expression(name, branch_index: nil, run_index: nil)
      node_id = node_id_for_expression_name(name)
      if node_id
        run = node_run(node_id, run_index)
        if run
          output_index = branch_index.nil? ? default_branch_index_for(node_id) : branch_index.to_i
          output_items = run.dig("outputs", output_index)
          return output_items if output_items.is_a?(Array)
          return []
        end
      end

      items = @context[name]
      return items if items.is_a?(Array)
      return [{ "json" => items }] if items.is_a?(Hash)

      []
    end

    def default_branch_index_for(name)
      target_node_id = node_id_for_expression_name(name)
      input_source = current_input_source
      if target_node_id && input_source&.dig("node_id").to_s == target_node_id.to_s
        return input_source["output_index"].to_i
      end

      0
    end

    def trace_linked_items(node_id, output_index, item_index, target_node_id, visited)
      key = [node_id.to_s, output_index.to_i, item_index.to_i]
      return [] if visited.include?(key)

      visited.add(key)
      output_item = output_item_for(node_id, output_index, item_index)
      return [] unless output_item

      if node_id.to_s == target_node_id.to_s
        return [
          {
            node_id: node_id.to_s,
            output_index: output_index.to_i,
            item_index: item_index.to_i,
            item: output_item,
          },
        ]
      end

      paired_items = normalized_paired_items(output_item)
      raise MISSING_ITEM_LINK_MESSAGE if paired_items.blank?

      paired_items.flat_map do |paired_item|
        source = input_source_for(node_id, paired_item.fetch("input") { 0 })
        next [] if source.blank?

        trace_linked_items(
          source["node_id"],
          source["output_index"].to_i,
          paired_item.fetch("item").to_i,
          target_node_id,
          visited.dup,
        )
      end
    end

    def output_item_for(node_id, output_index, item_index)
      node_run(node_id)&.dig("outputs", output_index.to_i, item_index.to_i)
    end

    def input_source_for(node_id, input_index)
      node_run(node_id)&.dig("input_sources", input_index.to_i)
    end

    def node_run(node_id, run_index = nil)
      runs = Array(@context.dig("__node_runs", node_id.to_s))
      return if runs.blank?

      return runs.last if run_index.nil?

      runs[run_index.to_i] || runs.last
    end

    def normalized_paired_items(item)
      paired_item = Item.paired_item(item)
      return [] if paired_item.blank?

      paired_items = paired_item.is_a?(Array) ? paired_item : [paired_item]
      paired_items.filter_map do |entry|
        next { "item" => entry, "input" => 0 } if entry.is_a?(Integer)
        next unless entry.is_a?(Hash) && entry["item"].is_a?(Integer)

        { "item" => entry["item"], "input" => entry["input"] || 0 }
      end
    end

    def current_input_source
      input_index = @context.fetch("__current_input_index") { 0 }.to_i
      Array(@context["__input_sources"] || @context[:__input_sources])[input_index]
    end

    def node_id_for_expression_name(name)
      @context.dig("__node_ids_by_name", name) || (@context.dig("__node_runs", name) && name)
    end
  end
end
