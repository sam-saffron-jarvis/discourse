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
              handler: "waiting_show",
            },
            {
              name: "default",
              path: "",
              http_method: "POST",
              response_mode: "response_node",
              restart_webhook: true,
              node_type: "form",
              handler: "waiting_submit",
            },
            {
              name: "status",
              path: "status",
              http_method: "GET",
              response_mode: "on_received",
              restart_webhook: true,
              node_type: "form",
              handler: "waiting_status",
            },
          ],
        )

        def self.handle_waiting_webhook(webhook, request)
          public_send(webhook.fetch(:handler), request)
        end

        def self.waiting_status(request)
          WaitingDispatch::Response.new(status: :ok, body: { status: "form_waiting" })
        end

        def self.waiting_show(request)
          result =
            DiscourseWorkflows::Form::Show.call(
              request.service_params.deep_merge(
                params: {
                  execution_id: request.execution_id,
                  signature: request.signature,
                },
              ),
            )
          return form_show_response(result, request.execution) if result.success?
          raise Discourse::NotLoggedIn if failed?(result, "result.policy.authenticated_if_required")

          not_found_or_unprocessable(result)
        end

        def self.waiting_submit(request)
          result =
            DiscourseWorkflows::Form::Resume.call(
              request.service_params.deep_merge(
                params: {
                  execution_id: request.execution_id,
                  signature: request.signature,
                  form_data: request.params[:form_data] || {},
                },
              ),
            )

          return form_resume_response(result[:claimed_execution].reload) if result.success?
          return invalid_form_response(result) if failed?(result, "result.step.ensure_form_valid")
          return already_resumed_response if failed?(result, "result.model.claimed_execution")

          not_found_or_unprocessable(result)
        end

        def execute(exec_ctx)
          item = exec_ctx.input_items.first || { "json" => {} }
          page_type = exec_ctx.get_node_parameter("page_type", item, default: "page")

          return [exec_ctx.input_items] if page_type == "completion"

          exec_ctx.put_execution_to_wait(nil)
          [exec_ctx.input_items]
        end

        def self.form_show_response(result, execution)
          WaitingDispatch::Response.new(
            status: :ok,
            body: result[:form_data].merge(WaitingExecution.form_urls(execution)),
          )
        end
        private_class_method :form_show_response

        def self.form_resume_response(execution)
          body = { status: execution.status }

          if WaitingDispatch.waiting_for?(execution, node_type: "form")
            body.merge!(WaitingExecution.form_urls(execution))
          elsif execution.success?
            body[:form_completion] = FormCompletion.from_execution(execution)
          end

          WaitingDispatch::Response.new(status: :ok, body: body.compact)
        end
        private_class_method :form_resume_response

        def self.invalid_form_response(result)
          WaitingDispatch::Response.new(
            status: :unprocessable_entity,
            body: {
              errors: result[:form_validation].errors.map(&:to_h),
            },
          )
        end
        private_class_method :invalid_form_response

        def self.already_resumed_response
          WaitingDispatch::Response.new(
            status: :conflict,
            body: {
              error: I18n.t("discourse_workflows.errors.already_resumed"),
            },
          )
        end
        private_class_method :already_resumed_response

        def self.not_found_or_unprocessable(result)
          if failed?(
               result,
               "result.policy.valid_waiting_request",
               "result.policy.action_form",
               "result.model.waiting_execution",
               "result.model.form_node",
               "result.model.execution",
               "result.model.waiting_node",
             )
            return WaitingDispatch::Response.new(status: :not_found, body: { error: "not_found" })
          end

          WaitingDispatch::Response.new(status: :unprocessable_entity, body: { success: false })
        end
        private_class_method :not_found_or_unprocessable

        def self.failed?(result, *keys)
          keys.any? { |key| result[key]&.failure? }
        end
        private_class_method :failed?
      end
    end
  end
end
