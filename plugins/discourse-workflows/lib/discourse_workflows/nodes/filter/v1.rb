# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Filter
      class V1 < NodeType
        description(
          name: "condition:filter",
          version: "1.0",
          defaults: {
            icon: "filter",
            color: "violet",
          },
          outputs: [
            { key: "true", label_key: "discourse_workflows.executions.statuses.kept" },
            { key: "false", label_key: "discourse_workflows.executions.statuses.rejected" },
          ],
          properties: {
            combinator: {
              type: :options,
              options: %w[and or],
              default: "and",
              ui: {
                expression: false,
              },
            },
            conditions: {
              type: :array,
              ui: {
                control: :condition_builder,
              },
            },
            options: {
              type: :object,
              ui: {
                hidden: true,
              },
            },
          },
        )

        def execute(exec_ctx)
          kept, rejected =
            exec_ctx.input_items.partition { |item| exec_ctx.get_parameter(:conditions, item) }

          [kept, rejected]
        end
      end
    end
  end
end
