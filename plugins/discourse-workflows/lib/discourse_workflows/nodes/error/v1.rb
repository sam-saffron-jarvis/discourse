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
          output_schema: {
            error_message: :string,
            failed_node_name: :string,
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
