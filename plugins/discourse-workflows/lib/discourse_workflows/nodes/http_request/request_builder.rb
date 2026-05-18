# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module HttpRequest
      class RequestBuilder
        include HttpHelpers

        def initialize(config, exec_ctx = nil)
          @config = config
          @exec_ctx = exec_ctx
        end

        def build
          method = @config.fetch("method") { "GET" }.downcase.to_sym
          if @config["url"].blank?
            raise I18n.t("discourse_workflows.errors.http_request.url_required")
          end

          uri = build_uri(@config["url"], @config["query_params"])
          headers = (@config["headers"] || {}).to_h.compact
          Authenticator.apply(@config, headers, @exec_ctx)
          body = @config.key?("body") ? @config["body"] : build_body(method, @config, headers)
          [method, uri, headers, body]
        end

        private

        def build_uri(url, query_params)
          uri = URI.parse(url)
          if %w[http https].exclude?(uri.scheme&.downcase)
            raise I18n.t("discourse_workflows.errors.http_request.unsupported_scheme")
          end
          raise I18n.t("discourse_workflows.errors.http_request.host_required") if uri.host.blank?

          append_query_params(uri, query_params)
          uri
        end

        def append_query_params(uri, query_params)
          return if query_params.blank?

          existing = URI.decode_www_form(uri.query || "")
          query_params.each { |qp| existing << [qp["key"], qp["value"]] if qp["key"].present? }
          uri.query = URI.encode_www_form(existing) if existing.any?
        end
      end
    end
  end
end
