# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module TopicCreated
      class V1 < NodeType
        description(
          name: "trigger:topic_created",
          version: "1.0",
          defaults: {
            icon: "plus",
            color: "teal",
          },
          group: "discourse_triggers",
          output_schema: {
            topic: Schemas::Topic.fields,
          },
          events: [:topic_created],
        )

        def initialize(topic, opts = nil, *)
          super(configuration: {})
          @topic = topic
          @opts = opts
        end

        def valid?
          @topic.present? && !skip_workflows?(@opts)
        end

        def output
          { topic: Schemas::Topic.serialize(@topic) }
        end
      end
    end
  end
end
