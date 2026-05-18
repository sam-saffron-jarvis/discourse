# frozen_string_literal: true

module DiscourseWorkflows
  class Webhook::Receive
    include Service::Base

    params do
      attribute :execution_id, :integer
      attribute :token, :string
      attribute :webhook_suffix, :string
      attribute :path, :string
      attribute :http_method, :string
      attribute :body, default: -> { {} }
      attribute :headers, default: -> { {} }
      attribute :query_params, default: -> { {} }
      attribute :raw_authorization, :string

      validates :http_method, presence: true

      def webhook_url
        if execution_id.present?
          DiscourseWorkflows::WaitingExecution.webhook_url_with_signature(
            execution_id: execution_id,
            signature: token,
            suffix: webhook_suffix,
          )
        else
          "#{Discourse.base_url}/workflows/webhooks/#{path}"
        end
      end

      def trigger_data
        {
          body: body,
          headers: headers,
          query: query_params,
          method: http_method,
          webhook_url: webhook_url,
        }
      end

      def response_items
        [
          {
            "json" => {
              "body" => body,
              "headers" => headers,
              "query" => query_params,
              "method" => http_method,
              "webhook_url" => webhook_url,
            },
          },
        ]
      end
    end

    model :waiting_execution, optional: true
    policy :valid_resume_request

    only_if(:resuming_execution) do
      model :waiting_node
      policy :valid_http_method

      only_if(:async_resume?) { step :enqueue_async_resume }

      only_if(:sync_resume?) do
        model :claimed_execution
        model :sync_result, :resume_execution_synchronously
      end
    end

    only_if(:triggering_new_workflow) do
      model :webhook_nodes, :find_webhook_nodes
      model :authenticated_nodes, :filter_authenticated_nodes
      step :enqueue_async_workflows
      model :sync_result, :execute_sync_workflows, optional: true
    end

    private

    def valid_resume_request(waiting_execution:, params:)
      params.execution_id.blank? || waiting_execution.present?
    end

    def fetch_waiting_execution(params:)
      return nil if params.execution_id.blank? || params.token.blank?

      execution =
        DiscourseWorkflows::WaitingExecution.find(
          execution_id: params.execution_id,
          signature: params.token,
          expected_node_type: "flow:wait",
        )
      return nil unless execution

      waiting_node = execution.find_waiting_node
      return nil unless waiting_node

      suffix = params.webhook_suffix.to_s
      stored_suffix = NodeData.parameters(waiting_node)["webhook_suffix"].to_s
      return nil unless suffix == stored_suffix

      execution
    end

    def fetch_claimed_execution(waiting_execution:, params:)
      DiscourseWorkflows::WaitingExecution.claim(waiting_execution, signature: params.token)
    end

    def resuming_execution(waiting_execution:)
      waiting_execution.present?
    end

    def triggering_new_workflow(waiting_execution:, params:)
      waiting_execution.nil? && params.execution_id.blank?
    end

    def fetch_waiting_node(waiting_execution:)
      waiting_execution.find_waiting_node
    end

    def valid_http_method(waiting_node:, params:)
      NodeData.parameters(waiting_node)["http_method"] == params.http_method
    end

    def async_resume?(waiting_node:)
      response_mode =
        NodeData.parameters(waiting_node)["response_mode"] ||
          Schemas::Webhook::RESPONSE_MODE_IMMEDIATELY
      response_mode == Schemas::Webhook::RESPONSE_MODE_IMMEDIATELY
    end

    def sync_resume?(waiting_node:)
      !async_resume?(waiting_node:)
    end

    def enqueue_async_resume(waiting_execution:, params:)
      Jobs.enqueue(
        Jobs::DiscourseWorkflows::ResumeWebhookWaiting,
        execution_id: waiting_execution.id,
        response_items: params.response_items,
      )
    end

    def resume_execution_synchronously(claimed_execution:, waiting_node:, params:)
      parameters = NodeData.parameters(waiting_node)
      execution =
        DiscourseWorkflows::WaitingExecution.resume_claimed(
          claimed_execution,
          params.response_items,
        )
      {
        execution: execution,
        response_mode: parameters["response_mode"],
        response_code: parameters["response_code"],
      }
    end

    def find_webhook_nodes(params:)
      Workflow::Action::FindPublishedTriggers.call(
        trigger_type: "trigger:webhook",
        dependency_type: "webhook_path",
        dependency_key: params.path,
        filter:
          lambda do |published_trigger|
            node = published_trigger.trigger_node
            parameters = NodeData.parameters(node)
            parameters["path"] == params.path && parameters["http_method"] == params.http_method
          end,
      )
    end

    def filter_authenticated_nodes(webhook_nodes:, params:)
      credential_ids =
        webhook_nodes.filter_map do |published_trigger|
          node = published_trigger.trigger_node
          parameters = NodeData.resolved_parameters(node)
          credential_ref = NodeData.credentials(node)["auth"]
          if (parameters["authentication"] || "none") == "basic_auth"
            credential_ref["id"].to_i if credential_ref
          end
        end

      credentials = DiscourseWorkflows::Credential.where(id: credential_ids).index_by(&:id)

      webhook_nodes.select do |published_trigger|
        Webhook::Action::AuthenticateNode.call(
          node: published_trigger.trigger_node,
          params: params,
          credentials: credentials,
        )
      end
    end

    def enqueue_async_workflows(authenticated_nodes:, params:)
      authenticated_nodes.each do |published_trigger|
        node = published_trigger.trigger_node
        response_mode =
          NodeData.parameters(node)["response_mode"] || Schemas::Webhook::RESPONSE_MODE_IMMEDIATELY
        next unless response_mode == Schemas::Webhook::RESPONSE_MODE_IMMEDIATELY

        DiscourseWorkflows::TriggerDispatcher.enqueue(
          published_trigger,
          trigger_data: params.trigger_data,
        )
      end
    end

    def execute_sync_workflows(authenticated_nodes:, params:)
      first = nil
      authenticated_nodes.each do |published_trigger|
        node = published_trigger.trigger_node
        parameters = NodeData.parameters(node)
        response_mode = parameters["response_mode"] || Schemas::Webhook::RESPONSE_MODE_IMMEDIATELY
        next if response_mode == Schemas::Webhook::RESPONSE_MODE_IMMEDIATELY

        execution =
          DiscourseWorkflows::TriggerDispatcher.execute(
            published_trigger,
            trigger_data: params.trigger_data,
          )
        first ||= {
          execution: execution,
          response_mode: response_mode,
          response_code: parameters["response_code"],
        }
      end
      first
    end
  end
end
