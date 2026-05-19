# frozen_string_literal: true

require "ipaddr"

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
      attribute :path_params, default: -> { {} }
      attribute :query_params, default: -> { {} }
      attribute :raw_body, :string
      attribute :remote_ip, :string
      attribute :ips, default: -> { [] }
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
        webhook_request.item_json
      end

      def response_items
        [{ "json" => webhook_request.item_json }]
      end

      def webhook_request
        DiscourseWorkflows::WebhookRequest.new(
          method: http_method,
          path: path,
          headers: headers,
          params: path_params,
          query: query_params,
          body: body,
          raw_body: raw_body,
          ip: remote_ip,
          ips: ips,
          webhook_url: webhook_url,
        )
      end
    end

    model :waiting_execution, optional: true
    model :webhook_context, :build_webhook_context
    policy :valid_resume_request

    only_if(:resuming_execution) do
      model :waiting_node
      policy :valid_http_method

      only_if(:async_resume?) do
        step :enqueue_async_resume
        model :webhook_response, :immediate_resume_response
      end

      only_if(:sync_resume?) do
        model :claimed_execution
        model :sync_result, :resume_execution_synchronously
        model :webhook_response, :sync_response
      end
    end

    only_if(:triggering_new_workflow) do
      model :webhook_nodes, :find_webhook_nodes
      model :authenticated_nodes, :filter_authenticated_nodes
      model :request_allowed_nodes, :filter_request_allowed_nodes
      step :enqueue_async_workflows
      model :sync_result, :execute_sync_workflows, optional: true
      model :webhook_response, :trigger_response
    end

    private

    def build_webhook_context(params:)
      DiscourseWorkflows::WebhookContext.new(request: params.webhook_request)
    end

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
      wait_node_response_mode(waiting_node) == Schemas::Webhook::RESPONSE_MODE_ON_RECEIVED
    end

    def sync_resume?(waiting_node:)
      !async_resume?(waiting_node:)
    end

    def enqueue_async_resume(waiting_execution:, params:, webhook_context:)
      webhook_context.resume(params.response_items)

      Jobs.enqueue(
        Jobs::DiscourseWorkflows::ResumeWebhookWaiting,
        execution_id: waiting_execution.id,
        response_items: webhook_context.resume_items,
      )
    end

    def immediate_resume_response(waiting_node:)
      WebhookResponseBuilder.immediate(NodeData.parameters(waiting_node))
    end

    def resume_execution_synchronously(claimed_execution:, waiting_node:, params:, webhook_context:)
      parameters = NodeData.parameters(waiting_node)
      webhook_context.resume(params.response_items)
      execution =
        DiscourseWorkflows::WaitingExecution.resume_claimed(
          claimed_execution,
          webhook_context.resume_items,
          webhook_context: webhook_context,
        )
      {
        execution: execution,
        response_mode: parameters["response_mode"],
        response_code: parameters["response_code"],
        response_data: parameters["response_data"],
        response_parameters: parameters,
        webhook_context: webhook_context,
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

    def filter_request_allowed_nodes(authenticated_nodes:, params:)
      authenticated_nodes.select do |published_trigger|
        request_allowed?(published_trigger.trigger_node, params)
      end
    end

    def enqueue_async_workflows(request_allowed_nodes:, params:)
      request_allowed_nodes.each do |published_trigger|
        node = published_trigger.trigger_node
        response_mode = trigger_node_response_mode(node)
        next unless response_mode == Schemas::Webhook::RESPONSE_MODE_ON_RECEIVED

        DiscourseWorkflows::TriggerDispatcher.enqueue(
          published_trigger,
          trigger_data: params.trigger_data,
        )
      end
    end

    def execute_sync_workflows(request_allowed_nodes:, params:, webhook_context:)
      first = nil
      request_allowed_nodes.each do |published_trigger|
        node = published_trigger.trigger_node
        parameters = NodeData.parameters(node)
        response_mode = trigger_node_response_mode(node)
        next if response_mode == Schemas::Webhook::RESPONSE_MODE_ON_RECEIVED

        execution =
          DiscourseWorkflows::TriggerDispatcher.execute(
            published_trigger,
            trigger_data: params.trigger_data,
            webhook_context: webhook_context,
          )
        first ||= {
          execution: execution,
          response_mode: response_mode,
          response_code: parameters["response_code"],
          response_data: parameters["response_data"],
          response_parameters: parameters,
          webhook_context: webhook_context,
        }
      end
      first
    end

    def trigger_response(request_allowed_nodes:)
      sync_result = context[:sync_result]

      if sync_result
        sync_response(sync_result:)
      else
        WebhookResponseBuilder.immediate(
          NodeData.parameters(request_allowed_nodes.first.trigger_node),
        )
      end
    end

    def sync_response(sync_result:)
      case sync_result[:response_mode]
      when Schemas::Webhook::RESPONSE_MODE_RESPONSE_NODE
        sync_result[:webhook_context].response || WebhookResponse.success
      when Schemas::Webhook::RESPONSE_MODE_LAST_NODE
        WebhookResponseBuilder.last_node(
          sync_result[:execution],
          sync_result[:response_parameters] || {},
        )
      else
        WebhookResponse.success
      end
    end

    def wait_node_response_mode(waiting_node)
      NodeData.parameters(waiting_node)["response_mode"] ||
        Schemas::Webhook::RESPONSE_MODE_ON_RECEIVED
    end

    def trigger_node_response_mode(node)
      NodeData.parameters(node)["response_mode"] || Schemas::Webhook::RESPONSE_MODE_ON_RECEIVED
    end

    def request_allowed?(node, params)
      parameters = NodeData.parameters(node)
      if parameters["ignore_bots"] == true && bot_user_agent?(params.headers["user-agent"])
        return false
      end

      ip_allowlist = parameters["ip_allowlist"].to_s
      return true if ip_allowlist.blank?

      request_ips = ([params.remote_ip] + Array.wrap(params.ips)).compact.map(&:to_s)
      request_ips.any? { |ip| ip_allowed?(ip, ip_allowlist) }
    end

    def bot_user_agent?(user_agent)
      user_agent.to_s.match?(/bot|crawler|spider|preview|slurp|facebookexternalhit|whatsapp/i)
    end

    def ip_allowed?(ip, allowlist)
      return false if ip.blank?

      request_ip = IPAddr.new(ip)
      allowlist
        .split(",")
        .map(&:strip)
        .reject(&:blank?)
        .any? { |entry| ip_entry_allowed?(request_ip, entry) }
    rescue IPAddr::InvalidAddressError
      false
    end

    def ip_entry_allowed?(request_ip, entry)
      IPAddr.new(entry).include?(request_ip)
    rescue IPAddr::InvalidAddressError
      false
    end
  end
end
