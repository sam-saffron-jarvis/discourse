# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Code
      class ResultValidator
        N8N_ITEM_KEYS = %w[json binary pairedItem error index].freeze

        def initialize(normalize_items:, raise_error:)
          @normalize_items = normalize_items
          @raise_error = raise_error
        end

        def validate_each_item(result, item_index:)
          value = result["value"]

          if result["type"] != "object"
            raise_validation_error!(
              "Code doesn't return an object",
              "Please return an object representing the output item. " \
                "('#{value}' was returned instead.)",
              item_index:,
            )
          end

          if value.is_a?(Array)
            first_sentence =
              (
                if value.length > 0
                  "An array of #{value.first.class.name.downcase}s was returned."
                else
                  "An empty array was returned."
                end
              )
            raise_validation_error!(
              "Code doesn't return a single object",
              "#{first_sentence} If you need to output multiple items, please use the " \
                "'Run Once for All Items' mode instead.",
              item_index:,
            )
          end

          unless value.is_a?(Hash)
            raise_validation_error!(
              "Code doesn't return an object",
              "Please return an object representing the output item.",
              item_index:,
            )
          end

          return_data = normalize_items!([value]).first
          validate_item!(return_data, item_index:)
          validate_top_level_keys!(return_data, item_index:)
          return_data["pairedItem"] ||= { "item" => item_index }
          return_data
        end

        def validate_all_items(result)
          value = result["value"]

          if result["type"] != "object"
            raise_validation_error!(
              "Code doesn't return items properly",
              "Please return an array of objects, one for each item you would like to output.",
            )
          end

          if value.is_a?(Array)
            unless value.all? { |item| item.is_a?(Hash) }
              raise_validation_error!(
                "Code doesn't return items properly",
                "Please return an array of objects, one for each item you would like to output.",
              )
            end

            if value.any? { |item| item.keys.any? { |key| n8n_item_key?(key) } }
              value.each_with_index do |item, index|
                validate_top_level_keys!(item, item_index: index)
              end
            end
          elsif !value.is_a?(Hash)
            raise_validation_error!(
              "Code doesn't return items properly",
              "Please return an array of objects, one for each item you would like to output.",
            )
          end

          normalize_items!(value).tap do |return_data|
            return_data.each_with_index { |item, index| validate_item!(item, item_index: index) }
          end
        end

        private

        def normalize_items!(value)
          @normalize_items.call(value)
        rescue DiscourseWorkflows::Item::InconsistentItemFormatError => e
          raise_validation_error!("Inconsistent item format", e.message)
        end

        def validate_item!(item, item_index:)
          unless item["json"].is_a?(Hash)
            raise_validation_error!(
              "A 'json' property isn't an object",
              "In the returned data, every key named 'json' must point to an object.",
              item_index:,
            )
          end

          if item.key?("binary") && !item["binary"].is_a?(Hash)
            raise_validation_error!(
              "A 'binary' property isn't an object",
              "In the returned data, every key named 'binary' must point to an object.",
              item_index:,
            )
          end
        end

        def validate_top_level_keys!(item, item_index:)
          found_reserved_key = nil
          unknown_keys = []

          item.each_key do |key|
            if n8n_item_key?(key)
              found_reserved_key ||= key
            else
              unknown_keys << key
            end
          end

          return if unknown_keys.empty?

          if found_reserved_key
            raise_validation_error!(
              "Invalid output format",
              "An output item contains the reserved key #{found_reserved_key}. " \
                "Wrap each item in an object under a key called json.",
              item_index:,
            )
          end

          raise_validation_error!(
            "Unknown top-level item key: #{unknown_keys.first}",
            "Access the properties of an item under .json, e.g. item.json",
            item_index:,
          )
        end

        def raise_validation_error!(message, description, item_index: nil, line_number: nil)
          @raise_error.call(message, description:, item_index:, line_number:)
        end

        def n8n_item_key?(key)
          N8N_ITEM_KEYS.include?(key.to_s)
        end
      end
    end
  end
end
