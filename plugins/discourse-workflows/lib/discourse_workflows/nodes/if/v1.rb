# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module If
      class V1 < NodeType
        description(
          name: "condition:if",
          version: "1.0",
          defaults: {
            icon: "arrows-split-up-and-left",
            color: "blue",
          },
          outputs: [
            { key: "true", label_key: "discourse_workflows.branch.true" },
            { key: "false", label_key: "discourse_workflows.branch.false" },
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
          true_items, false_items =
            exec_ctx.input_items.partition { |item| exec_ctx.get_parameter(:conditions, item) }

          exec_ctx.branch("true" => true_items, "false" => false_items)
        end
      end
    end
  end
end
