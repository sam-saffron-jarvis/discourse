# frozen_string_literal: true

module DiscourseWorkflows
  class CredentialSerializer < ApplicationSerializer
    attributes :id, :name, :credential_type, :data, :data_modes, :created_at, :updated_at

    def data
      schema = Registry.find_credential_type(object.credential_type)&.property_schema || {}
      decrypted_data.each_with_object({}) do |(key, value), hash|
        field_schema = schema[key.to_sym] || {}
        hash[key] = (
          if field_schema.dig(:ui, :control) == :password
            Credential::REDACTED_VALUE
          else
            value
          end
        )
      end
    end

    def data_modes
      decrypted_data.transform_values do |value|
        value.is_a?(String) && value.start_with?("=") ? "expression" : "fixed"
      end
    end

    private

    def decrypted_data
      @decrypted_data ||= object.decrypted_data
    end
  end
end
