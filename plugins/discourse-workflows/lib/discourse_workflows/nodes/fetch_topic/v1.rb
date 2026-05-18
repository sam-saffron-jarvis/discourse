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
          items =
            exec_ctx.input_items.map.with_index do |_item, item_index|
              config = {
                "topic_id" => exec_ctx.get_node_parameter("topic_id", item_index),
                "actor_username" =>
                  exec_ctx.get_node_parameter("actor_username", item_index, default: "system"),
              }

              wrap(process(exec_ctx, config))
            end

          [items]
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
