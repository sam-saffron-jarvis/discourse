# frozen_string_literal: true

module DiscourseWorkflows
  module NodeData
    SETTINGS_PARAMETER_KEYS = %w[description].freeze

    module_function

    def parameters(node)
      read(node, "parameters") || {}
    end

    def credentials(node)
      read(node, "credentials") || {}
    end

    def resolved_parameters(node)
      parameters(node).deep_dup
    end

    def split(parameters:, credentials: {}, settings: {}, webhook_id: nil, node_type: nil)
      parameters = (parameters || {}).deep_stringify_keys
      settings = (settings || {}).deep_stringify_keys
      credentials = normalize_credentials(credentials)
      webhook_id = extract_webhook_id(parameters, webhook_id, node_type)

      SETTINGS_PARAMETER_KEYS.each do |key|
        settings[key] = parameters.delete(key) if parameters.key?(key)
      end

      remove_undeclared_credential_parameters(parameters, node_type)
      credentials = filter_declared_credentials(credentials, node_type, parameters)

      {
        "parameters" => parameters,
        "credentials" => credentials,
        "settings" => settings,
        "webhook_id" => webhook_id,
      }
    end

    def normalize_credentials(credentials_hash)
      (credentials_hash || {}).each_with_object({}) do |(slot, credential), result|
        next unless credential.is_a?(Hash)

        credential = credential.deep_stringify_keys
        next if credential["id"].blank?

        credential["credential_type"] ||= credential.delete("type")
        result[slot.to_s] = credential.slice("id", "credential_type").merge(
          "id" => credential["id"].to_s,
        )
      end
    end

    def read(node, key)
      return node.public_send(key) if node.respond_to?(key)

      node[key] || node[key.to_sym]
    end

    def filter_declared_credentials(credentials, node_type, parameters)
      return credentials if node_type.blank?

      definitions = credential_definitions_for(node_type)
      return {} if definitions.blank?

      definitions.each_with_object({}) do |definition, result|
        slot = definition["name"]
        credential = credentials[slot]
        next if credential.blank? || !credential_slot_visible?(definition, parameters)

        credential_type = credential["credential_type"].presence
        credential_types = credential_types_for(definition)
        credential_type ||= credential_types.first if credential_types.one?
        next if credential_type.blank? || credential_types.exclude?(credential_type)

        result[slot] = credential.merge("credential_type" => credential_type)
      end
    end

    def credential_definitions_for(node_type)
      normalize_credential_definitions(node_class(node_type)&.credentials)
    end

    def remove_undeclared_credential_parameters(parameters, node_type)
      return if node_type.blank? || !parameters.key?("credential_id")
      return if node_class(node_type)&.property_schema&.key?(:credential_id)

      parameters.delete("credential_id")
    end

    def normalize_credential_definitions(definitions)
      Array(definitions).filter_map do |definition|
        definition = definition.deep_stringify_keys
        name = definition["name"].presence
        next if name.blank?

        definition.merge("name" => name)
      end
    end

    def credential_types_for(definition)
      Array(definition["credential_types"] || definition["credential_type"]).map(&:to_s)
    end

    def credential_slot_visible?(definition, parameters)
      display_options = definition["displayOptions"] || definition["display_options"]
      return visible_for_conditions?(definition["visible_if"], parameters) if display_options.blank?

      visible_for_conditions?(display_options["show"], parameters) &&
        !hidden_by_conditions?(display_options["hide"], parameters)
    end

    def visible_for_conditions?(conditions, parameters)
      return true if conditions.blank?

      conditions.all? { |key, expected| Array(expected).map(&:to_s).include?(parameters[key].to_s) }
    end

    def hidden_by_conditions?(conditions, parameters)
      conditions.present? && visible_for_conditions?(conditions, parameters)
    end

    def extract_webhook_id(parameters, webhook_id, node_type)
      unless node_type == "trigger:form" || node_class(node_type)&.identifier == "trigger:form"
        return webhook_id
      end

      parameters.delete("uuid").presence || webhook_id
    end

    def node_class(node_type)
      node_type.respond_to?(:identifier) ? node_type : Registry.find_node_type(node_type)
    end
  end
end
