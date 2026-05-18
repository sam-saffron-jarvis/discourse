# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module HttpHelpers
      BODY_METHODS = %i[post put patch].freeze

      def normalize_headers(headers_config)
        rows = CollectionParameters.rows_from_value(headers_config)
        return headers_config.compact if rows.empty? && headers_config.is_a?(Hash)

        rows.each_with_object({}) do |h, headers|
          headers[h["key"]] = h["value"] if h["key"].present?
        end
      end

      def fixed_collection_rows(configuration, field_name, group: "values")
        CollectionParameters.rows(configuration, field_name, group: group)
      end

      def build_body(method, config, headers, form_params: nil)
        return nil if BODY_METHODS.exclude?(method)

        content_type = config.fetch("content_type") { "json" }

        case content_type
        when "form_urlencoded"
          form_params ||= fixed_collection_rows(config, "body_form")
          return nil if form_params.blank?
          headers["Content-Type"] = "application/x-www-form-urlencoded"
          URI.encode_www_form(
            form_params.filter_map { |p| [p["key"], p["value"]] if p["key"].present? },
          )
        when "raw"
          body = config["body_raw"]
          return nil if body.blank?
          headers["Content-Type"] = config.fetch("raw_content_type") { "text/plain" }
          body
        else
          body = config["body_json"]
          return nil if body.blank?
          headers["Content-Type"] ||= "application/json"
          body
        end
      end
    end
  end
end
