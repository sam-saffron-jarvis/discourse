# frozen_string_literal: true

module DiscourseWorkflows
  class LoadOptionsContext
    attr_reader :source_key,
                :property_name,
                :node_identifier,
                :node_version,
                :node_id,
                :node_name,
                :workflow_id,
                :parameters,
                :credentials,
                :search,
                :filter,
                :input_context,
                :execution_context,
                :user,
                :guardian,
                :node_class

    def self.coerce(value)
      value.is_a?(self) ? value : new(source_key: value)
    end

    def initialize(
      source_key:,
      property_name: nil,
      node_identifier: nil,
      node_version: nil,
      node_id: nil,
      node_name: nil,
      workflow_id: nil,
      parameters: {},
      credentials: {},
      search: nil,
      filter: nil,
      input_context: {},
      execution_context: {},
      user: nil,
      guardian: nil,
      node_class: nil
    )
      @source_key = source_key.to_s
      @property_name = property_name.presence&.to_s
      @node_identifier = node_identifier.presence&.to_s || node_class&.identifier
      @node_version = node_version.presence&.to_s || node_class&.version
      @node_id = node_id.presence&.to_s
      @node_name = node_name.presence&.to_s
      @workflow_id = workflow_id.presence&.to_s
      @parameters = normalize_hash(parameters)
      @node_class = node_class
      @credentials = filter_credentials(credentials)
      @search = search.presence&.to_s
      @filter = filter.presence&.to_s || @search
      @input_context = normalize_hash(input_context)
      @execution_context = normalize_hash(execution_context)
      @user = user
      @guardian = guardian
    end

    def current_node_parameter(path = nil, fallback = nil)
      return parameters if path.blank?

      value = dig_path(parameters, path)
      value.nil? ? fallback : value
    end
    alias get_current_node_parameter current_node_parameter

    def current_node_parameters
      parameters
    end
    alias get_current_node_parameters current_node_parameters

    def credential_reference(slot)
      direct_reference = credentials[slot.to_s]
      return direct_reference if direct_reference.present?

      definition = credential_definition(slot)
      credentials[definition["name"]] if definition.present?
    end

    def credential_reference?(slot)
      credential_reference(slot).present?
    end

    def get_credential(slot)
      definition = credential_definition(slot)
      reference = credential_reference(slot)
      raise Discourse::InvalidAccess if definition.blank? || reference.blank?

      credential = DiscourseWorkflows::Credential.find_by(id: reference["id"])
      raise Discourse::InvalidAccess if credential.blank?
      unless credential_type_allowed?(definition, credential.credential_type)
        raise Discourse::InvalidAccess
      end

      DiscourseWorkflows::ExpressionResolver.resolve_hash(
        credential.decrypted_data,
        context: credential_resolver_context,
        user: user,
      )
    end
    alias get_credentials get_credential

    def to_h
      {
        source_key: source_key,
        property_name: property_name,
        node_identifier: node_identifier,
        node_version: node_version,
        node_id: node_id,
        node_name: node_name,
        workflow_id: workflow_id,
        parameters: parameters,
        credentials: credentials,
        search: search,
        filter: filter,
        input_context: input_context,
        execution_context: execution_context,
      }.compact
    end

    private

    def normalize_hash(value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
      value = value.to_h if value.respond_to?(:to_h)
      value.is_a?(Hash) ? value.deep_stringify_keys : {}
    end

    def filter_credentials(credentials)
      normalized = NodeData.normalize_credentials(normalize_hash(credentials))
      definitions = credential_definitions
      return normalized if node_class.blank?
      return {} if definitions.blank?

      definitions.each_with_object({}) do |definition, result|
        slot = definition["name"]
        credential = normalized[slot]
        next if credential.blank? || !NodeData.credential_slot_visible?(definition, parameters)

        credential_type = credential["credential_type"].presence
        credential_types = NodeData.credential_types_for(definition)
        credential_type ||= credential_types.first if credential_types.one?
        next if credential_type.blank? || credential_types.exclude?(credential_type)

        result[slot] = credential.merge("credential_type" => credential_type)
      end
    end

    def credential_definitions
      @credential_definitions ||= NodeData.normalize_credential_definitions(node_class&.credentials)
    end

    def credential_definition(slot)
      credential_definitions.find { |definition| definition["name"] == slot.to_s } ||
        credential_definitions.find do |definition|
          NodeData.credential_types_for(definition).include?(slot.to_s)
        end
    end

    def credential_type_allowed?(definition, credential_type)
      NodeData.credential_types_for(definition).include?(credential_type.to_s)
    end

    def credential_resolver_context
      execution_context.merge(input_context).merge(
        "$json" => input_context.dig("item", "json") || {},
        "__input_item" => input_context["item"] || {},
      )
    end

    def dig_path(hash, path)
      path
        .to_s
        .split(".")
        .reject(&:blank?)
        .reduce(hash) do |value, key|
          break nil unless value.respond_to?(:[])

          if value.respond_to?(:key?) && value.key?(key)
            value[key]
          elsif value.respond_to?(:key?) && value.key?(key.to_sym)
            value[key.to_sym]
          end
        end
    end
  end
end
