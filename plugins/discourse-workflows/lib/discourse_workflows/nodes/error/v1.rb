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
          capabilities: {
            manually_triggerable: true,
          },
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

        def self.manual_mock_data(workflow)
          execution_id = 231

          {
            "execution" => {
              "id" => execution_id.to_s,
              "url" =>
                "#{Discourse.base_url}/admin/plugins/discourse-workflows/workflows/" \
                  "#{workflow.id}/executions/#{execution_id}",
              "retryOf" => "34",
              "error" => {
                "message" => "Example Error Message",
                "stack" => "Stacktrace",
              },
              "lastNodeExecuted" => "Node With Error",
              "mode" => "manual",
            },
            "workflow" => {
              "id" => workflow.id.to_s,
              "name" => workflow.name,
            },
          }
        end
      end
    end
  end
end
