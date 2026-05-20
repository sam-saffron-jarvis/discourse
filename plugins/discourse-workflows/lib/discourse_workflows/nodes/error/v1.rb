# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Error
      class V1 < NodeType
        description(
          name: "trigger:error",
          version: "1.0",
          defaults: {
            icon: "triangle-exclamation",
            color: "red",
          },
          inputs: [],
          max_nodes: 1,
          output_schema: {
            execution: {
              id: :string,
              url: :string,
              retryOf: :string,
              error: :object,
              lastNodeExecuted: :string,
              mode: :string,
              executionContext: :object,
            },
            trigger: {
              error: :object,
              mode: :string,
            },
            workflow: {
              id: :string,
              name: :string,
            },
          },
        )

        def initialize(error_data = {}, *)
          super(parameters: {})
          @error_data = error_data.is_a?(Hash) ? error_data : {}
        end

        def valid?
          true
        end

        def output
          @error_data
        end
      end
    end
  end
end
