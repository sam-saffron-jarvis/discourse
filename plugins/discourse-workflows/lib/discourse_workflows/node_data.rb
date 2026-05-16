# frozen_string_literal: true

module DiscourseWorkflows
  module NodeData
    SETTINGS_PARAMETER_KEYS = %w[description].freeze
    CREDENTIAL_PARAMETER_KEYS = %w[credential_id].freeze
    AUTH_CREDENTIAL_TYPES = %w[basic_auth bearer_token].freeze

    module_function

    def parameters(node)
      read(node, "parameters") || {}
    end

    def credentials(node)
      read(node, "credentials") || {}
    end

    def resolved_parameters(node)
      parameters(node).deep_dup.merge(credential_parameters(credentials(node)))
    end

    def credential_parameters(credentials_hash)
      normalize_credentials(credentials_hash).each_with_object({}) do |(_slot, credential), result|
        field_name = credential["field_name"].presence
        next if field_name.blank?

        result[field_name] = credential["id"]
      end
    end

    def split(parameters:, credentials: {}, settings: {}, webhook_id: nil, node_type: nil)
      parameters = (parameters || {}).deep_stringify_keys
      settings = (settings || {}).deep_stringify_keys
      credentials = normalize_credentials(credentials)
      webhook_id = extract_webhook_id(parameters, webhook_id, node_type)

      SETTINGS_PARAMETER_KEYS.each do |key|
        settings[key] = parameters.delete(key) if parameters.key?(key)
      end

      if parameters.key?("authentication")
        sync_auth_credential_type(parameters, credentials)
      else
        credentials.delete("auth")
      end
      extract_credentials(parameters, credentials)

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

        result[slot.to_s] = credential.merge("id" => credential["id"].to_s)
      end
    end

    def read(node, key)
      return node.public_send(key) if node.respond_to?(key)

      node[key] || node[key.to_sym]
    end

    def extract_credentials(parameters, credentials)
      CREDENTIAL_PARAMETER_KEYS.each do |field_name|
        next unless parameters.key?(field_name)

        value = parameters.delete(field_name)
        if value.blank?
          credentials.delete("auth")
          next
        end

        credential_type = credential_type_for(parameters)
        if credential_type.blank?
          credentials.delete("auth")
          next
        end

        credentials["auth"] = {
          "id" => value.to_s,
          "field_name" => field_name,
          "credential_type" => credential_type,
        }.compact
      end
    end

    def credential_type_for(parameters)
      authentication = parameters["authentication"].to_s
      authentication if AUTH_CREDENTIAL_TYPES.include?(authentication)
    end

    def sync_auth_credential_type(parameters, credentials)
      return unless parameters.key?("authentication")

      credential_type = credential_type_for(parameters)
      if credential_type.blank?
        credentials.delete("auth")
      elsif credentials["auth"].present?
        if credentials["auth"]["field_name"].blank? || credentials["auth"]["credential_type"].blank?
          credentials.delete("auth")
          return
        end

        credentials["auth"]["credential_type"] = credential_type
      end
    end

    def extract_webhook_id(parameters, webhook_id, node_type)
      return webhook_id unless node_type == "trigger:form"

      parameters.delete("uuid").presence || webhook_id
    end
  end
end
