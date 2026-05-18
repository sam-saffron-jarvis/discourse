# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module HttpRequest
      class V1 < NodeType
        include HttpHelpers

        description(
          name: "action:http_request",
          version: "1.0",
          defaults: {
            icon: "globe",
            color: "indigo",
          },
          properties: {
            method: {
              type: :options,
              required: true,
              options: %w[GET POST PUT DELETE PATCH],
              default: "GET",
              ui: {
                expression: true,
              },
            },
            url: {
              type: :string,
              required: true,
            },
            authentication: {
              type: :options,
              options: %w[none basic_auth bearer_token],
              default: "none",
              ui: {
                expression: false,
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
            query_params: {
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
            content_type: {
              type: :options,
              required: false,
              options: %w[json form_urlencoded raw],
              default: "json",
              visible_if: {
                method: %w[POST PUT PATCH],
              },
            },
            body_json: {
              type: :string,
              required: false,
              visible_if: {
                method: %w[POST PUT PATCH],
                content_type: "json",
              },
              ui: {
                control: :textarea,
              },
            },
            body_raw: {
              type: :string,
              required: false,
              visible_if: {
                method: %w[POST PUT PATCH],
                content_type: "raw",
              },
              ui: {
                control: :textarea,
              },
            },
            body_form: {
              type: :fixed_collection,
              required: false,
              visible_if: {
                method: %w[POST PUT PATCH],
                content_type: "form_urlencoded",
              },
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
            raw_content_type: {
              type: :string,
              required: false,
              default: "text/plain",
              visible_if: {
                method: %w[POST PUT PATCH],
                content_type: "raw",
              },
            },
            never_error: {
              type: :boolean,
              required: false,
              default: false,
            },
            full_response: {
              type: :boolean,
              required: false,
              default: false,
            },
            max_response_size_kb: {
              type: :integer,
              required: false,
              default: 1024,
            },
          },
          credentials: [
            {
              name: "auth",
              credential_types: %w[basic_auth bearer_token],
              required: false,
              displayOptions: {
                show: {
                  authentication: %w[basic_auth bearer_token],
                },
              },
              label_key: "discourse_workflows.http_request.credential",
            },
          ],
        )

        def execute(exec_ctx)
          items =
            exec_ctx.input_items.flat_map do |item|
              exec_ctx.with_item(item) do
                config = exec_ctx.get_parameters(item)
                result = process(config, item, exec_ctx)
                wrap_result(result, paired_item: exec_ctx.paired_item_for(item))
              end
            end
          [items]
        end

        private

        def process(config, item, exec_ctx)
          method = config.fetch("method") { "GET" }.downcase.to_sym
          headers = normalize_headers(exec_ctx.get_fixed_collection_rows("headers", item))
          body =
            build_body(
              method,
              config,
              headers,
              form_params: exec_ctx.get_fixed_collection_rows("body_form", item),
            )
          log_request(exec_ctx.log, method, config["url"], headers, body)
          response =
            exec_ctx.http_request(
              method: method,
              url: config["url"],
              headers: headers,
              body: body,
              options:
                request_options(config, exec_ctx.get_fixed_collection_rows("query_params", item)),
            )
          if full_response?(config)
            {
              body: response.body,
              headers: response.headers,
              statusCode: response.status,
              statusMessage: response.status_message,
            }
          else
            response.body
          end
        end

        def full_response?(config)
          config["full_response"] == true || config["fullResponse"] == true
        end

        def wrap_result(result, paired_item:)
          if result.is_a?(Array)
            result.map { |entry| wrap_response_body(entry, paired_item:) }
          else
            [wrap_response_body(result, paired_item:)]
          end
        end

        def wrap_response_body(body, paired_item:)
          wrap(body.is_a?(Hash) ? body : { data: body }, paired_item:)
        end

        def log_request(log, method, uri, headers, body)
          log.info("#{method.to_s.upcase} #{uri}")
          if headers.present?
            filtered =
              ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(
                headers,
              )
            filtered.each { |k, v| log.info("#{k}: #{v}") }
          end
          if body.is_a?(Hash)
            filtered_body =
              ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(
                body,
              )
            log.info(filtered_body.to_json)
          elsif body.present?
            log.info("[body omitted]")
          end
        end

        def request_options(config, query_params)
          config.slice("authentication", "never_error", "max_response_size_kb").merge(
            "query_params" => query_params,
          )
        end
      end
    end
  end
end
