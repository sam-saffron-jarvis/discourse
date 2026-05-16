# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module FormTrigger
      class V1 < NodeType
        description(
          name: "trigger:form",
          version: "1.0",
          defaults: {
            icon: "rectangle-list",
            color: "teal",
          },
          properties: {
            url_preview: {
              type: :custom,
              required: false,
              ui: {
                control: :url_preview,
              },
            },
            form_title: {
              type: :string,
            },
            form_description: {
              type: :string,
              ui: {
                control: :textarea,
              },
            },
            form_fields: Schemas::FormFields::SCHEMA,
            authentication: {
              type: :options,
              required: true,
              default: "none",
              options: %w[none login_required],
              ui: {
                expression: false,
              },
            },
            response_mode: {
              type: :options,
              required: true,
              default: "on_received",
              options: %w[on_received workflow_finishes],
              ui: {
                expression: false,
              },
            },
          },
          output_schema: Schemas::FormFields::FORM_TRIGGER_OUTPUT_SCHEMA,
          capabilities: {
            manually_triggerable: true,
            provides_current_user: true,
          },
          webhooks: [{ name: "default", path: "webhook_id", http_method: "GET" }],
        )

        def initialize(
          form_data:,
          submitted_at: Time.current.utc.iso8601(3),
          form_mode: DiscourseWorkflows::FormPayload::DEFAULT_FORM_MODE,
          query_parameters: nil
        )
          super(parameters: {})
          @form_data = form_data
          @submitted_at = submitted_at
          @form_mode = form_mode
          @query_parameters = query_parameters
        end

        def output
          DiscourseWorkflows::FormPayload.build(
            @form_data,
            submitted_at: @submitted_at,
            form_mode: @form_mode,
            query_parameters: @query_parameters,
          )
        end
      end
    end
  end
end
