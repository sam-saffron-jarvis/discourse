# frozen_string_literal: true

module DiscourseWorkflows
  class FormsController < ::ApplicationController
    requires_plugin DiscourseWorkflows::PLUGIN_NAME

    FORM_SHOW_RATE_LIMIT = 30
    FORM_SHOW_RATE_PERIOD = 60

    skip_before_action :verify_authenticity_token
    skip_before_action :redirect_to_login_if_required
    skip_before_action :check_xhr

    before_action :check_form_show_rate_limit, only: %i[show waiting_show waiting_status]
    before_action :check_form_submit_rate_limit, only: :create
    before_action :check_form_resume_rate_limit, only: :waiting_create
    before_action :verify_request_origin, only: %i[create waiting_create]

    def show
      if request.format.json?
        DiscourseWorkflows::Form::Show.call(
          service_params.deep_merge(params: { form_query_parameters: form_query_parameters }),
        ) do
          on_success { |form_data:| render json: form_data }
          on_failed_policy(:authenticated_if_required) { raise Discourse::NotLoggedIn }
          on_failed_policy(:action_form) { raise Discourse::NotFound }
          on_failure { render(json: failed_json, status: :unprocessable_entity) }
          on_model_not_found(:published_trigger) { raise Discourse::NotFound }
          on_model_not_found(:form_node) { raise Discourse::NotFound }
        end
      else
        render html: "", layout: "application"
      end
    end

    def create
      DiscourseWorkflows::Form::Submit.call(service_params) do
        on_success do |execution:, response_metadata:|
          render json: form_submission_response(execution, response_metadata)
        end
        on_failed_policy(:authenticated_if_required) { raise Discourse::NotLoggedIn }
        on_failed_step(:ensure_form_valid) do |form_validation:|
          render json: { errors: form_validation.errors.map(&:to_h) }, status: :unprocessable_entity
        end
        on_failure { render(json: failed_json, status: :unprocessable_entity) }
        on_model_not_found(:published_trigger) { raise Discourse::NotFound }
      end
    end

    def waiting_status
      execution = find_waiting_form_execution
      return render json: { error: "not_found" }, status: :not_found if execution.nil?

      render json: waiting_status_payload(execution)
    end

    def waiting_show
      execution = find_waiting_form_execution
      return render json: { error: "not_found" }, status: :not_found if execution.nil?

      DiscourseWorkflows::Form::Show.call(
        service_params.deep_merge(
          params: {
            execution_id: execution.id,
            signature: waiting_signature,
          },
        ),
      ) do
        on_success { |form_data:| render json: form_data.merge(waiting_form_urls(execution)) }
        on_failed_policy(:authenticated_if_required) { raise Discourse::NotLoggedIn }
        on_failed_policy(:valid_waiting_request) { raise Discourse::NotFound }
        on_failed_policy(:action_form) { raise Discourse::NotFound }
        on_failure { render(json: failed_json, status: :unprocessable_entity) }
        on_model_not_found(:waiting_execution) { raise Discourse::NotFound }
        on_model_not_found(:form_node) { raise Discourse::NotFound }
      end
    end

    def waiting_create
      DiscourseWorkflows::Form::Resume.call(
        service_params.deep_merge(
          params: {
            execution_id: params[:execution_id].to_i,
            signature: waiting_signature,
            form_data: submitted_form_data,
          },
        ),
      ) do
        on_success do |claimed_execution:|
          render json: waiting_submission_response(claimed_execution.reload)
        end
        on_failed_step(:ensure_form_valid) do |form_validation:|
          render json: { errors: form_validation.errors.map(&:to_h) }, status: :unprocessable_entity
        end
        on_failed_policy(:action_form) { raise Discourse::NotFound }
        on_model_not_found(:claimed_execution) do
          render json: {
                   error: I18n.t("discourse_workflows.errors.already_resumed"),
                 },
                 status: :conflict
        end
        on_failure { render(json: failed_json, status: :unprocessable_entity) }
        on_model_not_found(:execution) { raise Discourse::NotFound }
        on_model_not_found(:waiting_node) { raise Discourse::NotFound }
      end
    end

    private

    def check_form_show_rate_limit
      RateLimiter.new(
        nil,
        "workflow_form_show:#{request.remote_ip}",
        FORM_SHOW_RATE_LIMIT,
        FORM_SHOW_RATE_PERIOD,
      ).performed!
    end

    def check_form_submit_rate_limit
      RateLimiter.new(current_user, "workflow_form_submit:#{request.remote_ip}", 10, 60).performed!
    end

    def check_form_resume_rate_limit
      RateLimiter.new(current_user, "workflow_form_resume:#{request.remote_ip}", 10, 60).performed!
    end

    def verify_request_origin
      origin = request.origin || request.headers["Origin"]
      raise Discourse::InvalidAccess if origin.blank?
      raise Discourse::InvalidAccess if URI.parse(origin).host != Discourse.current_hostname
    rescue URI::InvalidURIError
      raise Discourse::InvalidAccess
    end

    def form_query_parameters
      request.query_parameters.except(
        "resume_token",
        DiscourseWorkflows::WaitingExecution::SIGNATURE_PARAM,
      )
    end

    def waiting_signature
      request.query_parameters[DiscourseWorkflows::WaitingExecution::SIGNATURE_PARAM].presence
    end

    def submitted_form_data
      form_data = params[:form_data] || {}
      return form_data.to_unsafe_h if form_data.respond_to?(:to_unsafe_h)

      form_data
    end

    def find_waiting_form_execution
      DiscourseWorkflows::WaitingExecution.find(
        execution_id: params[:execution_id].to_i,
        signature: waiting_signature,
        expected_node_type: "action:form",
      )
    end

    def form_submission_response(execution, response_metadata)
      payload = {
        has_downstream_form: response_metadata[:has_downstream_form],
        response_mode: response_metadata[:response_mode],
        status: execution&.status,
      }

      if execution&.waiting? && execution.find_waiting_node&.dig("type") == "action:form"
        payload.merge!(waiting_form_urls(execution))
      elsif execution&.success?
        payload[:form_completion] = form_completion(execution)
      end

      payload.compact
    end

    def waiting_submission_response(execution)
      payload = { status: execution.status }

      if execution.waiting? && execution.find_waiting_node&.dig("type") == "action:form"
        payload.merge!(waiting_form_urls(execution))
      elsif execution.success?
        payload[:form_completion] = form_completion(execution)
      end

      payload.compact
    end

    def form_completion(execution)
      execution.execution_data&.context_data&.dig("__form_completion")
    end

    def waiting_status_payload(execution)
      status =
        if execution.find_waiting_node&.dig("type") == "action:form"
          "form_waiting"
        else
          execution.status
        end
      { status: status }
    end

    def waiting_form_urls(execution)
      {
        form_channel: DiscourseWorkflows::WaitingExecution.form_channel(execution),
        form_waiting_url: DiscourseWorkflows::WaitingExecution.form_waiting_url(execution),
        form_submit_url: DiscourseWorkflows::WaitingExecution.form_waiting_url(execution),
        form_status_url: DiscourseWorkflows::WaitingExecution.form_status_url(execution),
      }
    end
  end
end
