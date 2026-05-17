# frozen_string_literal: true

module DiscourseWorkflows
  class NodeTypesController < ::Admin::AdminController
    requires_plugin DiscourseWorkflows::PLUGIN_NAME

    def index
      DiscourseWorkflows::NodeType::List.call(service_params) do |result|
        on_success do |node_types:, credential_types:, expression_context:|
          render json: {
                   node_types: node_types,
                   credential_types: credential_types,
                   expression_context: expression_context,
                 }
        end
        on_failure { render(json: failed_json, status: :unprocessable_entity) }
        on_failed_policy(:can_manage_workflows) { raise Discourse::InvalidAccess }
      end
    end

    def options
      request_context = load_options_request_context
      version = params[:version].presence || request_context.dig("node", "type_version")
      node_class =
        DiscourseWorkflows::Registry.find_node_type(params[:identifier], version: version)
      raise Discourse::NotFound unless node_class.respond_to?(:load_options_context)

      context =
        DiscourseWorkflows::LoadOptionsContext.new(
          source_key: params[:source_key],
          property_name: request_context["property_name"],
          node_identifier: params[:identifier],
          node_version: version,
          node_id: request_context.dig("node", "id"),
          node_name: request_context.dig("node", "name"),
          workflow_id: request_context["workflow_id"],
          parameters: request_context["parameters"],
          credentials: request_context["credentials"],
          search: request_context["search"],
          filter: request_context["filter"],
          input_context: request_context["input_context"],
          execution_context: request_context["execution_context"],
          user: current_user,
          guardian: guardian,
          node_class: node_class,
        )

      options = node_class.load_options_context(context)
      raise Discourse::NotFound if options.nil?

      render json: { options: options }
    end

    private

    def load_options_request_context
      {
        "property_name" => params[:property_name],
        "parameters" => hash_param(:parameters),
        "credentials" => hash_param(:credentials),
        "search" => params[:search],
        "filter" => params[:filter],
        "node" => hash_param(:node),
        "workflow_id" => params[:workflow_id],
        "input_context" => hash_param(:input_context),
        "execution_context" => hash_param(:execution_context),
      }
    end

    def hash_param(key)
      value = params[key]
      value = JSON.parse(value) if value.is_a?(String) && value.start_with?("{")
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
      value if value.is_a?(Hash)
    end
  end
end
