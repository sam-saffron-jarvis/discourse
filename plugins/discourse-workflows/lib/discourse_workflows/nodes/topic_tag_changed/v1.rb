# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module TopicTagChanged
      class V1 < NodeType
        description(
          name: "trigger:topic_tag_changed",
          version: "1.0",
          defaults: {
            icon: "tag",
            color: "deep-orange",
          },
          group: "discourse_triggers",
          output_schema: {
            topic: Schemas::Topic.fields,
            old_tags: :array,
            new_tags: :array,
            added_tags: :array,
            removed_tags: :array,
          },
          events: [:topic_tags_changed],
        )

        def initialize(topic, payload = {})
          super(parameters: {})
          @topic = topic
          @old_tag_names = payload[:old_tag_names] || []
          @new_tag_names = payload[:new_tag_names] || []
          @user = payload[:user]
        end

        def valid?
          @topic.present?
        end

        def output
          {
            topic: Schemas::Topic.serialize(@topic),
            old_tags: @old_tag_names,
            new_tags: @new_tag_names,
            added_tags: @new_tag_names - @old_tag_names,
            removed_tags: @old_tag_names - @new_tag_names,
          }
        end
      end
    end
  end
end
