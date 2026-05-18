# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module RespondToWebhook
      class V1 < NodeType
        include Nodes::HttpHelpers

        DEFAULT_STATUS_CODES = { "redirect" => 302, "json" => 200, "text" => 200, "no_data" => 204 }

        description(
          name: "action:respond_to_webhook",
          version: "1.0",
          defaults: {
            icon: "reply",
            color: "purple",
          },
          properties: {
            response_type: {
              type: :options,
              required: true,
              default: "json",
              options: %w[json redirect text no_data],
            },
            status_code: {
              type: :string,
              required: false,
              default: "200",
              visible_if: {
                response_type: %w[json text no_data],
              },
            },
            redirect_url: {
              type: :string,
              required: true,
              visible_if: {
                response_type: %w[redirect],
              },
            },
            allowed_redirect_domains: {
              type: :fixed_collection,
              visible_if: {
                response_type: %w[redirect],
              },
              type_options: {
                multiple_values: true,
              },
              options: [{ name: "values", values: { domain: { type: :string, required: true } } }],
            },
            response_body: {
              type: :string,
              required: false,
              visible_if: {
                response_type: %w[json text],
              },
              ui: {
                control: :textarea,
              },
            },
            headers: {
              type: :fixed_collection,
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
          output_schema: {
            response_type: :string,
            status_code: :integer,
            redirect_url: :string,
            allowed_redirect_domains: :array,
            response_body: :string,
            headers: :object,
          },
        )

        def execute(exec_ctx)
          map_input_items(exec_ctx) do |config, item, item_index|
            process(exec_ctx, item, item_index, config)
          end
        end

        private

        def process(exec_ctx, _item, item_index, config)
          response_type = config.fetch("response_type") { "json" }
          status_code = (config["status_code"].presence || DEFAULT_STATUS_CODES[response_type]).to_i
          status_code = DEFAULT_STATUS_CODES[response_type] if response_type == "redirect"

          {
            response_type: response_type,
            status_code: status_code,
            redirect_url: config["redirect_url"],
            allowed_redirect_domains:
              normalize_allowed_redirect_domains(
                exec_ctx.get_fixed_collection_rows("allowed_redirect_domains", item_index),
              ),
            response_body: config["response_body"],
            headers: normalize_headers(exec_ctx.get_fixed_collection_rows("headers", item_index)),
          }
        end

        def normalize_allowed_redirect_domains(domain_rows)
          domain_rows.filter_map do |domain_config|
            domain_config["domain"].to_s.strip.downcase.presence
          end
        end
      end
    end
  end
end
