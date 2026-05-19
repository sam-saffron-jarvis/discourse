# frozen_string_literal: true

module DiscourseWorkflows
  class WebhookContext
    attr_reader :request, :response, :resume_items

    def initialize(request:)
      @request = request
      @response = nil
      @resume_items = nil
    end

    def respond(response)
      return false if responded?

      @response = WebhookResponse.coerce(response)
      true
    end

    def responded?
      response.present?
    end

    def resume(items)
      return false if resumed?

      @resume_items = items
      true
    end

    def resumed?
      !resume_items.nil?
    end
  end
end
