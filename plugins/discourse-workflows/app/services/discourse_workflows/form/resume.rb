# frozen_string_literal: true

module DiscourseWorkflows
  class Form::Resume
    include Service::Base

    policy :workflows_enabled, class_name: DiscourseWorkflows::Policy::WorkflowsEnabled

    params do
      attribute :action_token, :string
      attribute :resume_token, :string
      attribute :action_type, :string
      attribute :form_data, default: -> { {} }

      before_validation { self.resume_token, self.action_type = action_token.to_s.split(":", 2) }

      validates :resume_token, presence: true
      validates :action_type, presence: true
      validate :form_data_must_be_hash

      def form_data_must_be_hash
        errors.add(:form_data, :invalid) unless form_data.is_a?(Hash)
      end
    end

    model :execution
    model :waiting_node
    policy :action_form
    model :form_validation, :validate_form
    step :ensure_form_valid
    model :claimed_execution
    step :resume_execution

    private

    def validate_form(waiting_node:, params:)
      FormSchema.validate(waiting_node, params.form_data)
    end

    def ensure_form_valid(form_validation:)
      unless form_validation.valid?
        fail!(I18n.t("discourse_workflows.errors.invalid_form_submission"))
      end
    end

    def fetch_execution(params:)
      DiscourseWorkflows::Execution.by_resume_token(params.resume_token).includes(:workflow).first
    end

    def action_form(waiting_node:)
      waiting_node.dig("type") == "action:form"
    end

    def fetch_waiting_node(execution:)
      execution.workflow.find_node(execution.waiting_node_id)
    end

    def fetch_claimed_execution(execution:, params:)
      DiscourseWorkflows::Execution.claim_for_resume(execution, resume_token: params.resume_token)
    end

    def resume_execution(execution:, claimed_execution:, form_validation:, guardian:)
      form_data = execution.accumulated_form_data.merge(form_validation.data)

      response_items = [
        { "json" => { "form_data" => form_data, "submitted_at" => Time.current.utc.iso8601 } },
      ]
      DiscourseWorkflows::Executor.resume(claimed_execution, response_items, user: guardian.user)
    end
  end
end
