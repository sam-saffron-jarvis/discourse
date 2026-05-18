# frozen_string_literal: true

module DiscourseWorkflows
  WebhookResponse =
    Data.define(:status, :body, :workflow_data) do
      def self.respond(status:, body: {})
        new(status: status, body: body, workflow_data: nil)
      end

      def self.resume(workflow_data:, status: :ok, body: {})
        new(status: status, body: body, workflow_data: workflow_data)
      end

      def resume?
        workflow_data.present?
      end
    end
end
