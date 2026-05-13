# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module StaleTopic
      class V1 < NodeType
        description(
          name: "trigger:stale_topic",
          version: "1.0",
          defaults: {
            icon: "clock",
            color: "deep-orange",
          },
          group: "discourse_triggers",
          properties: {
            hours: {
              type: :integer,
              required: true,
              default: 24,
              min: 1,
            },
          },
          output_schema: {
            topic: Schemas::Topic.fields,
          },
        )

        def initialize(topic)
          super(configuration: {})
          @topic = topic
        end

        def output
          { topic: Schemas::Topic.serialize(@topic) }
        end
      end
    end
  end
end
