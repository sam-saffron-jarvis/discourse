# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module DataTable
      class V1 < NodeType
        OPERATIONS = %w[insert get update delete upsert].freeze
        MAPPING_MODES = %w[manual auto].freeze

        description(
          name: "action:data_table",
          version: "1.0",
          defaults: {
            icon: "table",
            color: "violet",
          },
          group: "data",
          properties: {
            operation: {
              type: :options,
              required: true,
              options: OPERATIONS,
              default: "insert",
            },
            data_table_id: {
              type: :integer,
              required: true,
              type_options: {
                load_options_method: "data_tables",
              },
              ui: {
                control: :data_table_select,
              },
              control_options: {
                value_property: "id",
                name_property: "name",
                filterable: true,
                none: "discourse_workflows.data_table_node.data_table_id_placeholder",
                resets: %w[filter columns sort_column output_fields],
              },
            },
            mapping_mode: {
              type: :options,
              required: true,
              options: MAPPING_MODES,
              default: "manual",
              visible_if: {
                operation: "insert",
              },
              no_data_expression: true,
            },
            columns_case_sensitive_hint: {
              type: :notice,
              visible_if: {
                operation: "insert",
                mapping_mode: "manual",
              },
            },
            columns: {
              type: :object,
              required: false,
              default: {
              },
              visible_if: {
                operation: %w[insert update upsert],
              },
              visible_unless: {
                mapping_mode: "auto",
              },
              ui: {
                control: :data_table_columns,
              },
            },
            filter_combinator: {
              type: :options,
              options: %w[and or],
              default: "and",
              required: false,
              visible_if: {
                operation: %w[get update delete upsert],
              },
              no_data_expression: true,
            },
            filter: {
              type: :array,
              required: false,
              visible_if: {
                operation: %w[get update delete upsert],
              },
              ui: {
                control: :data_table_condition_builder,
              },
            },
            limit: {
              type: :integer,
              required: false,
              visible_if: {
                operation: "get",
              },
            },
            sort_column: {
              type: :string,
              required: false,
              visible_if: {
                operation: "get",
              },
              ui: {
                control: :data_table_column_select,
                format: :full,
              },
              control_options: {
                none: "discourse_workflows.data_table_node.sort_column_placeholder",
              },
            },
            sort_direction: {
              type: :options,
              required: false,
              options: %w[asc desc],
              default: "asc",
              visible_if: {
                operation: "get",
              },
            },
            output_fields: {
              type: :array,
              required: false,
              ui: {
                hidden: true,
              },
            },
          },
        )

        def self.property_i18n_scope
          "data_table_node"
        end

        def self.operation_label_key(operation)
          "#{property_i18n_prefix}.#{property_i18n_scope}.operations.#{operation}"
        end

        def self.load_options_context(context)
          case context.method_name
          when "data_tables"
            result =
              context.helpers.get_data_table_aggregate_proxy.get_many_and_count(
                filter: {
                  name: context.filter,
                },
                sort_by: "name:asc",
              )

            result[:data]
          end
        end

        def execute(exec_ctx)
          items =
            exec_ctx.input_items.flat_map.with_index do |item, item_index|
              config = exec_ctx.get_node_parameters(item_index)
              pair_output_items(execute_with_config(config, item, exec_ctx), exec_ctx, item)
            end

          [items]
        end

        private

        def pair_output_items(output_items, exec_ctx, item)
          paired_item = exec_ctx.paired_item_for(item)

          Array.wrap(output_items).map { |output_item| with_paired_item(output_item, paired_item) }
        end

        def execute_with_config(config, item, exec_ctx)
          node_proxy = exec_ctx.helpers.get_data_table_proxy(config.fetch("data_table_id"))
          operation_name = config.fetch("operation", "insert")

          if operation_name == "insert" && config["mapping_mode"] == "auto"
            json = item["json"] || {}
            config = config.merge("columns" => json.slice(*node_proxy.column_names))
          end

          result =
            case operation_name
            when "insert"
              node_proxy.insert(columns: config["columns"])
            when "get"
              node_proxy.get(
                **filter_options(config),
                limit: config["limit"]&.to_i,
                sort_column: config["sort_column"],
                sort_direction: config["sort_direction"],
              )
            when "update"
              {
                "updated_count" =>
                  node_proxy.update(**filter_options(config), columns: config["columns"]),
              }
            when "delete"
              { "deleted_count" => node_proxy.delete(**filter_options(config)) }
            when "upsert"
              upsert_output(node_proxy, config)
            else
              raise ArgumentError,
                    I18n.t(
                      "discourse_workflows.errors.data_table.unknown_operation",
                      operation: operation_name,
                    )
            end

          wrap(result)
        end

        def upsert_output(node_proxy, config)
          result = node_proxy.upsert(**filter_options(config), columns: config["columns"])

          if result[:operation] == "update"
            { "operation" => "update", "count" => result[:updated_count] }
          else
            { "operation" => "insert" }.merge(result[:row])
          end
        end

        def filter_options(config)
          { filter: config["filter"], filter_combinator: config["filter_combinator"] }
        end
      end
    end
  end
end
