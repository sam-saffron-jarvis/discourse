# frozen_string_literal: true

module DiscourseWorkflows
  module FormResponse
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
      end

      payload.compact
    end

    def resumed_submission(execution)
      body = { status: execution.status }

      if DiscourseWorkflows::WaitingWebhookRunner.waiting_for?(execution, node_type: "form")
        body.merge!(DiscourseWorkflows::WaitingExecution.form_urls(execution))
      elsif execution.success?
        body[:form_completion] = DiscourseWorkflows::FormCompletion.from_execution(execution)
      end

      body.compact
    end
  end
end
