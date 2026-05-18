# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Form
      class V1 < NodeType
        description(
          name: "action:form",
          version: "1.0",
          defaults: {
            icon: "rectangle-list",
            color: "blue",
          },
          group: "human_review",
          properties: {
            page_type: {
              type: :options,
              default: "page",
              options: %w[page completion],
              no_data_expression: true,
            },
            form_title: {
              type: :string,
              visible_if: {
                page_type: %w[page],
              },
            },
            form_description: {
              type: :string,
              visible_if: {
                page_type: %w[page],
              },
              ui: {
                control: :textarea,
              },
            },
            form_fields: Schemas::FormFields::SCHEMA.merge(visible_if: { page_type: %w[page] }),
            on_submission: {
              type: :options,
              default: "completion_screen",
              options: %w[completion_screen redirect show_text],
              visible_if: {
                page_type: %w[completion],
              },
              no_data_expression: true,
            },
            completion_title: {
              type: :string,
              visible_if: {
                page_type: %w[completion],
                on_submission: %w[completion_screen],
              },
            },
            completion_message: {
              type: :string,
              visible_if: {
                page_type: %w[completion],
                on_submission: %w[completion_screen],
              },
              ui: {
                control: :textarea,
              },
            },
            redirect_url: {
              type: :string,
              visible_if: {
                page_type: %w[completion],
                on_submission: %w[redirect],
              },
            },
            completion_text: {
              type: :string,
              visible_if: {
                page_type: %w[completion],
                on_submission: %w[show_text],
              },
              ui: {
                control: :textarea,
              },
            },
          },
          output_schema: Schemas::FormFields::FORM_OUTPUT_SCHEMA,
          capabilities: {
            waits_for_resume: true,
          },
          webhooks: [
            {
              name: "setup",
              path: "",
              http_method: "GET",
              response_mode: "on_received",
              restart_webhook: true,
              node_type: "form",
            },
            {
              name: "default",
              path: "",
              http_method: "POST",
              response_mode: "response_node",
              restart_webhook: true,
              node_type: "form",
            },
            {
              name: "status",
              path: "status",
              http_method: "GET",
              response_mode: "on_received",
              restart_webhook: true,
              node_type: "form",
            },
          ],
        )

        def execute(exec_ctx)
          item = exec_ctx.input_items.first || { "json" => {} }
          page_type = exec_ctx.get_node_parameter("page_type", item, default: "page")

          return [exec_ctx.input_items] if page_type == "completion"

          exec_ctx.put_execution_to_wait(nil)
          [exec_ctx.input_items]
        end

        def webhook(webhook_ctx)
          return status_response if webhook_ctx.http_method == "GET" && webhook_ctx.path == "status"
          return show_response(webhook_ctx) if webhook_ctx.http_method == "GET"
          return submit_response(webhook_ctx) if webhook_ctx.http_method == "POST"

          DiscourseWorkflows::WebhookResponse.respond(
            status: :not_found,
            body: {
              error: "not_found",
            },
          )
        end

        private

        def status_response
          DiscourseWorkflows::WebhookResponse.respond(status: :ok, body: { status: "form_waiting" })
        end

        def show_response(webhook_ctx)
          DiscourseWorkflows::WebhookResponse.respond(status: :ok, body: form_data(webhook_ctx))
        end

        def submit_response(webhook_ctx)
          form_validation =
            DiscourseWorkflows::FormSchema.validate(webhook_ctx.node, form_data_param(webhook_ctx))

          unless form_validation.valid?
            return(
              DiscourseWorkflows::WebhookResponse.respond(
                status: :unprocessable_entity,
                body: {
                  errors: form_validation.errors.map(&:to_h),
                },
              )
            )
          end

          DiscourseWorkflows::WebhookResponse.resume(
            workflow_data: [
              [{ "json" => Payload.build(form_validation.data, form_mode: webhook_ctx.form_mode) }],
            ],
          )
        end

        def form_data_param(webhook_ctx)
          webhook_ctx.params[:form_data] || webhook_ctx.params["form_data"] || {}
        end

        def form_data(webhook_ctx)
          item = webhook_ctx.input_items.first || { "json" => {} }

          {
            uuid: webhook_ctx.trigger_node_webhook_id,
            form_title: webhook_ctx.get_node_parameter("form_title", item),
            form_description: webhook_ctx.get_node_parameter("form_description", item),
            form_fields:
              fields_with_query_defaults(
                Workflow.resolve_field_keys(
                  webhook_ctx.get_fixed_collection_rows("form_fields", item),
                ),
                webhook_ctx.form_query_parameters,
              ),
            response_mode: "on_received",
            has_downstream_form: webhook_ctx.node_has_reachable_downstream_of_type?("action:form"),
          }.compact
        end

        def fields_with_query_defaults(fields, query_parameters)
          normalized_query_parameters = query_parameters.with_indifferent_access

          fields.map do |field|
            key = field["key"]
            next field unless normalized_query_parameters.key?(key)

            field.merge("default_value" => normalized_query_parameters[key])
          end
        end
      end
    end
  end
end
