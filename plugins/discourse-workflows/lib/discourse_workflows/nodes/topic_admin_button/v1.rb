# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module TopicAdminButton
      class V1 < NodeType
        description(
          name: "trigger:topic_admin_button",
          version: "1.0",
          defaults: {
            icon: "gear",
            color: "cyan",
          },
          group: "discourse_triggers",
          properties: {
            label: {
              type: :string,
              required: true,
            },
            icon: {
              type: :icon,
              required: false,
            },
          },
          output_schema: {
            topic: Schemas::Topic.fields,
          },
          capabilities: {
            manually_triggerable: true,
            provides_current_user: true,
          },
        )

        def initialize(topic)
          super(configuration: {})
          @topic = topic
        end

        def valid?
          @topic.present?
        end

        def output
          { topic: Schemas::Topic.serialize(@topic) }
        end
      end
    end
  end
end
