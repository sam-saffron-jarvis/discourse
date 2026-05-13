# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Limit
      class V1 < NodeType
        description(
          name: "action:limit",
          version: "1.0",
          defaults: {
            icon: "magnifying-glass-minus",
            color: "yellow",
          },
          group: "flow",
          properties: {
            max_items: {
              type: :integer,
              required: false,
              default: 10,
            },
            keep: {
              type: :options,
              required: false,
              options: %w[first last],
              default: "first",
            },
          },
        )

        def execute(exec_ctx)
          max = @configuration.fetch("max_items") { 10 }.to_i
          keep = @configuration.fetch("keep") { "first" }

          items =
            if keep == "last"
              exec_ctx.input_items.last(max)
            else
              exec_ctx.input_items.first(max)
            end
          [items]
        end
      end
    end
  end
end
