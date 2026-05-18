# frozen_string_literal: true

module DiscourseWorkflows
  module FormResponse
    WORKFLOW_FINISHES_RESPONSE_MODE = "workflow_finishes"

    module_function

    def initial_submission(execution, response_metadata)
      payload = {
        has_downstream_form: response_metadata[:has_downstream_form],
        response_mode: response_metadata[:response_mode],
        status: execution&.status,
      }

      if DiscourseWorkflows::WaitingWebhookRunner.waiting_for?(execution, node_type: "form")
        payload.merge!(DiscourseWorkflows::WaitingExecution.form_urls(execution))
      elsif execution&.success?
        payload[:form_completion] = DiscourseWorkflows::FormCompletion.from_execution(execution)
      elsif execution&.error?
        payload[:error] = workflow_error_message
      end

      payload.compact
    end

    def initial_submission_status(execution, response_metadata)
      if response_metadata[:response_mode] == WORKFLOW_FINISHES_RESPONSE_MODE && execution&.error?
        return :internal_server_error
      end

      :ok
    end

    def resumed_submission(execution)
      body = { status: execution.status }

      if DiscourseWorkflows::WaitingWebhookRunner.waiting_for?(execution, node_type: "form")
        body.merge!(DiscourseWorkflows::WaitingExecution.form_urls(execution))
      elsif execution.success?
        body[:form_completion] = DiscourseWorkflows::FormCompletion.from_execution(execution)
      elsif execution.error?
        body[:error] = workflow_error_message
      end

      body.compact
    end

    def resumed_submission_status(execution)
      return :internal_server_error if execution.error?

      :ok
    end

    def workflow_error_message
      I18n.t("discourse_workflows.errors.workflow_failed")
    end
  end
end
