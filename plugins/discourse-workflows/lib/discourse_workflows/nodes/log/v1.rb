# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Log
      class V1 < NodeType
        description(
          name: "action:log",
          version: "1.0",
          defaults: {
            icon: "scroll",
            color: "purple",
          },
          properties: {
            entries: {
              type: :fixed_collection,
              required: false,
              type_options: {
                multiple_values: true,
              },
              options: [
                {
                  name: "values",
                  values: {
                    key: {
                      type: :string,
                      required: true,
                      no_data_expression: true,
                    },
                    value: {
                      type: :string,
                      required: true,
                    },
                  },
                },
              ],
            },
          },
        )

        def execute(exec_ctx)
          entries = exec_ctx.get_node_parameter("entries.values", 0, default: [])
          return [exec_ctx.input_items] if entries.empty?

          entries.each { |entry| exec_ctx.log.kv(entry["key"].to_s, entry["value"].to_s) }

          [exec_ctx.input_items]
        end
      end
    end
  end
end
