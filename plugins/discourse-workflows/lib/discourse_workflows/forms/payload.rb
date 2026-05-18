# frozen_string_literal: true

module DiscourseWorkflows
  module Forms
    module Payload
      DEFAULT_MODE = "production"

      module_function

      def build(
        form_data,
        submitted_at: Time.current.utc.iso8601(3),
        form_mode: DEFAULT_MODE,
        query_parameters: nil
      )
        payload = (form_data || {}).deep_stringify_keys
        payload["submittedAt"] = submitted_at
        payload["formMode"] = form_mode.presence || DEFAULT_MODE

        if (query_parameters = normalize_query_parameters(query_parameters)).present?
          payload["formQueryParameters"] = query_parameters
        end

        payload
      end

      def normalize_query_parameters(query_parameters)
        query_parameters.present? ? query_parameters.to_h.deep_stringify_keys : {}
      end

      def form_mode_from(trigger_data)
        trigger_data.to_h["formMode"].presence || DEFAULT_MODE
      end

      def query_parameters_from(trigger_data)
        trigger_data.to_h["formQueryParameters"] || {}
      end
    end
  end
end
