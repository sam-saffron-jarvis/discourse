# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Webhook
      class V1 < NodeType
        description(
          name: "trigger:webhook",
          version: "1.0",
          defaults: {
            icon: "globe",
            color: "purple",
          },
          properties: {
            url_preview: {
              type: :custom,
              required: false,
              ui: {
                control: :url_preview,
              },
            },
            **Schemas::Webhook::CONFIGURATION_FIELDS,
            path: {
              type: :string,
              required: true,
            },
          },
          output_schema: Schemas::Webhook::OUTPUT_FIELDS,
          capabilities: {
            manually_triggerable: true,
          },
          credentials: [{ name: "auth", field_name: "credential_id", required: false }],
          webhooks: [{ name: "default", path: "path", http_method: "http_method" }],
        )

        def initialize(body:, headers:, query:, method:, webhook_url:)
          super(parameters: {})
          @body = body
          @headers = headers
          @query = query
          @method = method
          @webhook_url = webhook_url
        end

        def output
          {
            body: @body,
            headers: @headers,
            query: @query,
            method: @method,
            webhook_url: @webhook_url,
          }
        end
      end
    end
  end
end
