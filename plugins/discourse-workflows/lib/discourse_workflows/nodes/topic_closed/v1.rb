# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module TopicClosed
      class V1 < NodeType
        description(
          name: "trigger:topic_closed",
          version: "1.0",
          defaults: {
            icon: "lock",
            color: "grey",
          },
          group: "discourse_triggers",
          output_schema: {
            topic: Schemas::Topic.fields,
          },
          events: [:topic_status_updated],
        )

        def initialize(topic, status, enabled)
          super(configuration: {})
          @topic = topic
          @status = status
          @enabled = enabled
        end

        def valid?
          @status.to_s == "closed" && @enabled
        end

        def output
          { topic: Schemas::Topic.serialize(@topic) }
        end
      end
    end
  end
end
