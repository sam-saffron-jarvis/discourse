# frozen_string_literal: true

module DiscourseWorkflows
  class Form::Show
    include Service::Base

    params do
      attribute :uuid, :string
      attribute :execution_id, :integer
      attribute :signature, :string
      attribute :form_query_parameters, default: -> { {} }

      validates :uuid, presence: true, unless: :execution_id
      validates :signature, presence: true, if: :execution_id
      validate :form_query_parameters_must_be_hash

      def form_query_parameters_must_be_hash
        errors.add(:form_query_parameters, :invalid) unless form_query_parameters.is_a?(Hash)
      end
    end

    model :waiting_execution, optional: true
    policy :valid_waiting_request

    only_if(:resuming?) do
      model :workflow, :fetch_workflow_from_execution
      model :form_node, :fetch_form_node_from_execution
      policy :action_form
      model :form_data, :build_form_data_from_execution
    end

    only_if(:initial_request?) do
      model :published_trigger, :fetch_published_trigger_by_uuid
      model :workflow, :fetch_workflow_from_published_trigger
      model :workflow_version, :fetch_workflow_version_from_published_trigger
      model :form_node, :fetch_form_node_from_published_trigger
      policy :authenticated_if_required
      model :form_data, :build_form_data_from_config
    end

    private

    def resuming?(waiting_execution:)
      waiting_execution.present?
    end

    def initial_request?(waiting_execution:, params:)
      waiting_execution.blank? && params.execution_id.blank?
    end

    def valid_waiting_request(waiting_execution:, params:)
      params.execution_id.blank? || waiting_execution.present?
    end

    def authenticated_if_required(form_node:, guardian:)
      return true if NodeData.parameters(form_node)["authentication"] != "login_required"
      guardian.authenticated?
    end

    def fetch_waiting_execution(params:)
      return if params.execution_id.blank?

      DiscourseWorkflows::WaitingExecution.find(
        execution_id: params.execution_id,
        signature: params.signature,
      )
    end

    def action_form(form_node:)
      form_node.dig("type") == "action:form"
    end

    def fetch_workflow_from_execution(waiting_execution:)
      waiting_execution.workflow
    end

    def fetch_form_node_from_execution(waiting_execution:)
      waiting_execution.find_waiting_node
    end

    def fetch_published_trigger_by_uuid(params:)
      Form::Action::FindPublishedTrigger.call(uuid: params.uuid)
    end

    def fetch_workflow_from_published_trigger(published_trigger:)
      published_trigger.workflow
    end

    def fetch_workflow_version_from_published_trigger(published_trigger:)
      published_trigger.workflow_version
    end

    def fetch_form_node_from_published_trigger(published_trigger:)
      published_trigger.trigger_node
    end

    def build_form_data_from_execution(
      waiting_execution:,
      workflow:,
      form_node:,
      params:,
      guardian:
    )
      resume_token = waiting_execution.resume_token
      execution_data = waiting_execution.execution_data
      context_data = execution_data&.context_data || {}

      node_contexts_by_name =
        (execution_data&.node_contexts || {}).each_with_object({}) do |(id, value), acc|
          name = waiting_execution.workflow_node(id)&.dig("name").presence || id.to_s
          acc[name] = value
        end

      exec_context =
        context_data.merge(
          "__node_contexts" => node_contexts_by_name,
          "__execution" => {
            "id" => waiting_execution.id,
            "workflow_id" => workflow.id,
            "workflow_name" => waiting_execution.workflow_snapshot_name,
            "resume_url" =>
              DiscourseWorkflows::WaitingExecution.webhook_url(
                execution_id: waiting_execution.id,
                resume_token: resume_token,
              ),
          },
        )

      parameters = NodeData.parameters(form_node)

      {
        uuid: params.uuid || form_uuid_from_execution(waiting_execution),
        form_title:
          ExpressionResolver.resolve(
            parameters["form_title"],
            context: exec_context,
            user: guardian.user,
          ),
        form_description:
          ExpressionResolver.resolve(
            parameters["form_description"],
            context: exec_context,
            user: guardian.user,
          ),
        form_fields:
          fields_with_query_defaults(
            Workflow.resolve_field_keys(CollectionParameters.rows(parameters, "form_fields")),
            waiting_execution.trigger_data["formQueryParameters"] || {},
          ),
        response_mode: "on_received",
        has_downstream_form:
          waiting_execution.node_has_reachable_downstream_of_type?(form_node["id"], "action:form"),
      }
    end

    def form_uuid_from_execution(waiting_execution)
      waiting_execution.workflow_node(waiting_execution.trigger_node_id)&.dig("webhook_id")
    end

    def build_form_data_from_config(workflow:, workflow_version:, form_node:, params:, guardian:)
      resume_token =
        DiscourseWorkflows::FormTriggerToken.generate(
          workflow_id: workflow.id,
          trigger_node_id: form_node["id"],
          uuid: params.uuid,
          form_query_parameters: params.form_query_parameters,
        )

      exec_context = {
        "__execution" => {
          "workflow_id" => workflow.id,
          "workflow_name" => workflow_version.name,
          "resume_url" => "",
        },
      }

      config =
        ExpressionResolver.resolve_hash(
          NodeData.parameters(form_node).deep_stringify_keys,
          context: exec_context,
          user: guardian.user,
        )

      {
        uuid: params.uuid,
        form_title: config["form_title"],
        form_description: config["form_description"],
        form_fields:
          fields_with_query_defaults(
            Workflow.resolve_field_keys(CollectionParameters.rows(config, "form_fields")),
            params.form_query_parameters,
          ),
        response_mode: config["response_mode"] || "on_received",
        has_downstream_form:
          workflow.node_has_reachable_downstream_of_type?(
            form_node["id"],
            "action:form",
            published: true,
          ),
        resume_token: resume_token,
      }
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
