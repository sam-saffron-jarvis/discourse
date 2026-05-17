# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module FetchTopic
      class V1 < NodeType
        description(
          name: "action:fetch_topic",
          version: "1.0",
          defaults: {
            icon: "download",
            color: "light-blue",
          },
          group: "discourse_actions",
          properties: {
            topic_id: {
              type: :string,
              required: true,
            },
            actor_username: {
              type: :string,
              required: false,
              default: "system",
              ui: {
                control: :user,
              },
            },
          },
          output_schema: {
            topic: Schemas::Topic.fields,
          },
        )

        def execute(exec_ctx)
          map_input_items(exec_ctx) { |config| process(exec_ctx, config) }
        end

        private

        def process(exec_ctx, config)
          topic = Topic.find(config["topic_id"])
          actor = exec_ctx.find_user(username: config["actor_username"].presence || "system")
          actor.guardian.ensure_can_see!(topic)
          { topic: Schemas::Topic.serialize(topic) }
        end
      end
    end
  end
end
