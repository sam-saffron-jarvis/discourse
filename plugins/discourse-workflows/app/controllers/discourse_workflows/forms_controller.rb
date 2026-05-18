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
          body = DiscourseWorkflows::FormResponse.initial_submission(execution, response_metadata)
          status =
            DiscourseWorkflows::FormResponse.initial_submission_status(execution, response_metadata)
          render json: body, status: status
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
      render_waiting_webhook(path: "status")
    end

    def waiting_show
      render_waiting_webhook(path: "")
    end

    def waiting_create
      render_waiting_webhook(path: "", dispatch_params: { form_data: submitted_form_data })
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

    def render_waiting_webhook(path:, dispatch_params: {})
      result =
        DiscourseWorkflows::WaitingWebhookRunner.call(
          execution_id: params[:execution_id].to_i,
          signature: waiting_signature,
          http_method: request.method,
          path: path,
          node_type: "form",
          params: dispatch_params,
          service_params: service_params,
        )

      render json: result.body, status: result.status
    end
  end
end
