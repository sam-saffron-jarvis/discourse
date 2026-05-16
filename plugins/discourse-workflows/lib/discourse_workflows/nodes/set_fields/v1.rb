# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module SetFields
      class V1 < NodeType
        description(
          name: "action:set_fields",
          version: "1.0",
          defaults: {
            icon: "list",
            color: "green",
          },
          group: "data",
          properties: {
            mode: {
              type: :options,
              required: false,
              options: %w[manual raw],
              default: "manual",
            },
            assignments: {
              type: :assignment_collection,
              required: false,
              default: {
                assignments: [],
              },
              type_options: {
                assignment_types: %w[string number boolean array object],
              },
              visible_if: {
                mode: "manual",
              },
            },
            json_output: {
              type: :string,
              required: false,
              visible_if: {
                mode: "raw",
              },
              ui: {
                control: :code,
                expression: false,
              },
              control_options: {
                height: 200,
                lang: :json,
              },
            },
            include_other_fields: {
              type: :boolean,
              required: false,
              default: true,
            },
            include: {
              type: :options,
              required: false,
              options: %w[all selected except],
              default: "all",
              visible_if: {
                include_other_fields: true,
              },
            },
            include_fields: {
              type: :string,
              required: false,
              visible_if: {
                include_other_fields: true,
                include: "selected",
              },
            },
            exclude_fields: {
              type: :string,
              required: false,
              visible_if: {
                include_other_fields: true,
                include: "except",
              },
            },
            options: {
              type: :collection,
              required: false,
              options: [
                { name: "dot_notation", type: :boolean, default: true },
                { name: "ignore_conversion_errors", type: :boolean, default: false },
              ],
            },
          },
        )

        def execute(exec_ctx)
          items =
            exec_ctx.input_items.map do |item|
              config = exec_ctx.get_parameters(item)
              result = process(item, config)
              wrap(result)
            end
          exec_ctx.success(items)
        end

        private

        def process(item, config)
          item_json = item.fetch("json") { {} }
          result = included_fields(item_json, config)

          if config["mode"] == "raw"
            result.merge(parse_json_fields(config))
          else
            apply_assignments(result, config)
          end
        end

        def included_fields(item_json, config)
          return {} unless config.fetch("include_other_fields", true)

          dot_notation = dot_notation?(config)
          fields =
            case config.fetch("include") { "all" }
            when "selected"
              selected_fields(item_json, config["include_fields"], dot_notation)
            when "except"
              except_fields(item_json, config["exclude_fields"], dot_notation)
            else
              item_json.deep_dup
            end

          fields || {}
        end

        def parse_json_fields(config)
          raw_json = config["json_output"]
          if raw_json.blank?
            raise ArgumentError, I18n.t("discourse_workflows.errors.set_fields.json_blank")
          end

          parsed = JSON.parse(raw_json)
          unless parsed.is_a?(Hash)
            raise ArgumentError, I18n.t("discourse_workflows.errors.set_fields.json_must_be_object")
          end

          parsed
        end

        def apply_assignments(result, config)
          dot_notation = dot_notation?(config)
          ignore_errors = advanced_options(config).fetch("ignore_conversion_errors", false)

          CollectionParameters
            .assignments(config)
            .each do |field|
              key = field["name"].to_s
              next if key.blank?

              value = cast_value(field["value"], field.fetch("type") { "string" }, ignore_errors)
              set_field(result, key, value, dot_notation)
            end

          result
        end

        def selected_fields(item_json, field_list, dot_notation)
          split_fields(field_list).each_with_object({}) do |field, result|
            value = get_field(item_json, field, dot_notation)
            next if value.nil?

            output_field = dot_notation && field.include?(".") ? field.split(".").last : field
            set_field(result, output_field, value, dot_notation)
          end
        end

        def except_fields(item_json, field_list, dot_notation)
          result = item_json.deep_dup
          split_fields(field_list).each { |field| unset_field(result, field, dot_notation) }
          result
        end

        def split_fields(field_list)
          field_list.to_s.split(",").map(&:strip).reject(&:blank?)
        end

        def advanced_options(config)
          CollectionParameters.option_bag(config, "options")
        end

        def dot_notation?(config)
          advanced_options(config).fetch("dot_notation", true)
        end

        def cast_value(value, type, ignore_errors)
          cast_value!(value, type)
        rescue JSON::ParserError, ArgumentError, TypeError
          return value if ignore_errors

          raise
        end

        def cast_value!(value, type)
          case type
          when "integer"
            Integer(value)
          when "float"
            Float(value)
          when "number"
            Float(value)
          when "boolean"
            return value if value == true || value == false

            %w[true 1].include?(value.to_s.downcase)
          when "array"
            if value.is_a?(Array)
              value
            else
              JSON.parse(value.to_s).tap { |v| raise TypeError unless v.is_a?(Array) }
            end
          when "object"
            if value.is_a?(Hash)
              value
            else
              JSON.parse(value.to_s).tap { |v| raise TypeError unless v.is_a?(Hash) }
            end
          else
            value.to_s
          end
        end

        def set_field(result, field, value, dot_notation)
          unless dot_notation && field.include?(".")
            result[field] = value
            return
          end

          keys = field.split(".")
          leaf = keys.pop
          target = result
          keys.each do |key|
            target[key] = {} unless target[key].is_a?(Hash)
            target = target[key]
          end
          target[leaf] = value
        end

        def get_field(hash, field, dot_notation)
          return hash[field] unless dot_notation && field.include?(".")

          field.split(".").reduce(hash) { |value, key| value.is_a?(Hash) ? value[key] : nil }
        end

        def unset_field(hash, field, dot_notation)
          unless dot_notation && field.include?(".")
            hash.delete(field)
            return
          end

          keys = field.split(".")
          leaf = keys.pop
          target = keys.reduce(hash) { |value, key| value.is_a?(Hash) ? value[key] : nil }
          target.delete(leaf) if target.is_a?(Hash)
        end
      end
    end
  end
end
