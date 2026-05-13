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
          output_schema: Schemas::FormFields::OUTPUT_SCHEMA,
          capabilities: {
            manually_triggerable: true,
            provides_current_user: true,
          },
        )

        def initialize(form_data:, submitted_at:)
          super(configuration: {})
          @form_data = form_data
          @submitted_at = submitted_at
        end

        def output
          { form_data: @form_data, submitted_at: @submitted_at }
        end
      end
    end
  end
end
