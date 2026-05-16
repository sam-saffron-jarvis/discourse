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
                      ui: {
                        expression: false,
                      },
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
          raw_entries = CollectionParameters.rows(@configuration, "entries")
          return [exec_ctx.input_items] if raw_entries.empty?

          item = exec_ctx.input_items.first || { "json" => {} }
          config = exec_ctx.get_parameters(item)
          resolved_entries = CollectionParameters.rows(config, "entries")
          resolved_entries.each { |entry| exec_ctx.log.kv(entry["key"].to_s, entry["value"].to_s) }

          [exec_ctx.input_items]
        end
      end
    end
  end
end
