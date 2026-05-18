# frozen_string_literal: true

module DiscourseWorkflows
  class WaitingDispatch
    Response = Struct.new(:status, :body, keyword_init: true)

    Request =
      Struct.new(
        :execution,
        :signature,
        :http_method,
        :path,
        :params,
        :service_params,
        keyword_init: true,
      ) do
        def execution_id
          execution.id
        end
      end

    def self.call(...)
      new(...).call
    end

    def self.waiting_for?(execution, node_type:)
      return false unless execution&.waiting?

      node = execution.find_waiting_node
      return false if node.blank?

      node_class = Registry.find_node_type(node["type"], version: node["type_version"])
      return false unless node_class

      node_class.waiting_webhook_for(http_method: "GET", path: "", node_type: node_type).present?
    end

    def initialize(
      execution_id:,
      signature:,
      http_method:,
      path:,
      node_type:,
      params: {},
      service_params: {}
    )
      @execution_id = execution_id
      @signature = signature
      @http_method = http_method
      @path = path.to_s
      @node_type = node_type.to_s
      @params = params || {}
      @service_params = service_params || {}
    end

    def call
      execution = WaitingExecution.find(execution_id: @execution_id, signature: @signature)
      return not_found unless execution

      node = execution.find_waiting_node
      return not_found if node.blank?

      node_class = Registry.find_node_type(node["type"], version: node["type_version"])
      return not_found unless node_class

      webhook =
        node_class.waiting_webhook_for(
          http_method: @http_method,
          path: @path,
          node_type: @node_type,
        )
      return not_found unless webhook

      node_class.handle_waiting_webhook(
        webhook,
        Request.new(
          execution: execution,
          signature: @signature,
          http_method: @http_method,
          path: @path,
          params: @params,
          service_params: @service_params,
        ),
      )
    end

    private

    def not_found
      Response.new(status: :not_found, body: { error: "not_found" })
    end
  end
end
