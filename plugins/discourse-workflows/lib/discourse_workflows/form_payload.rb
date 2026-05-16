# frozen_string_literal: true

module DiscourseWorkflows
  module FormPayload
    DEFAULT_FORM_MODE = "production"

    def self.build(
      form_data,
      submitted_at: Time.current.utc.iso8601(3),
      form_mode: DEFAULT_FORM_MODE,
      query_parameters: nil
    )
      payload = (form_data || {}).deep_stringify_keys
      payload["submittedAt"] = submitted_at
      payload["formMode"] = form_mode.presence || DEFAULT_FORM_MODE

      normalized_query_parameters = normalize_query_parameters(query_parameters)
      if normalized_query_parameters.present?
        payload["formQueryParameters"] = normalized_query_parameters
      end

      payload
    end

    def self.normalize_query_parameters(query_parameters)
      return {} if query_parameters.blank?

      query_parameters.to_h.deep_stringify_keys
    end
  end
end
