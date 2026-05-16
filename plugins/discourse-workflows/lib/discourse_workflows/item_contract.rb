# frozen_string_literal: true

module DiscourseWorkflows
  module ItemContract
    class Error < StandardError
    end

    def self.validate_items!(items, source:)
      unless items.is_a?(Array) &&
               items.all? { |item| item.is_a?(Hash) && item["json"].is_a?(Hash) }
        raise Error,
              "Invalid items from #{source}: expected Array<{ 'json' => Hash }>, got #{items.inspect.truncate(200)}"
      end

      items.each { |item| validate_paired_item!(item, source:) }
    end

    def self.validate_output_arrays!(result, source:)
      unless result.is_a?(Array) && result.all? { |inner| inner.is_a?(Array) }
        raise Error, "#{source}: execute must return Array<Array<Item>>, got #{result.class}"
      end
      result.each { |inner| validate_items!(inner, source: source) }
    end

    def self.validate_node_result!(result, source:, ports:)
      unless result.is_a?(Executor::NodeResult)
        raise Error, "#{source}: execute must return Executor::NodeResult, got #{result.class}"
      end

      port_names = Array(ports).map { |port| port[:key].to_s }
      if port_names.present?
        unknown_outputs = result.outputs.keys - port_names
        if unknown_outputs.present?
          raise Error, "#{source}: unknown outputs #{unknown_outputs.inspect}"
        end
      elsif result.outputs.keys.many?
        raise Error, "#{source}: multiple outputs require declared ports"
      elsif result.outputs.keys.one? && result.outputs.keys.first != "main"
        raise Error, "#{source}: single output without declared ports must use 'main'"
      end

      result.outputs.each do |output_name, items|
        unless items.is_a?(Array)
          raise Error, "#{source}: output '#{output_name}' must contain an Array<Item>"
        end
        validate_items!(items, source: "#{source}:#{output_name}")
      end
    end

    def self.validate_paired_item!(item, source:)
      paired_item = Item.paired_item(item)
      return if paired_item.nil?

      entries = paired_item.is_a?(Array) ? paired_item : [paired_item]
      unless entries.all? { |entry| valid_paired_item_entry?(entry) }
        raise Error,
              "Invalid pairedItem from #{source}: expected { 'item' => Integer, 'input' => Integer? }, got #{paired_item.inspect.truncate(200)}"
      end
    end

    def self.valid_paired_item_entry?(entry)
      return false unless entry.is_a?(Hash)

      item_index = entry["item"]
      input_index = entry["input"]
      item_index.is_a?(Integer) && (input_index.nil? || input_index.is_a?(Integer))
    end
  end
end
