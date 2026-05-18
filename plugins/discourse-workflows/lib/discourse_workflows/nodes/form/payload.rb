# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Form
      module Payload
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

          if (query_parameters = normalize_query_parameters(query_parameters)).present?
            payload["formQueryParameters"] = query_parameters
          end

          payload
        end

        def self.normalize_query_parameters(query_parameters)
          query_parameters.present? ? query_parameters.to_h.deep_stringify_keys : {}
        end
      end
    end
  end
end
