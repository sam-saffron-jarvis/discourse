# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module CreatePost
      class V1 < NodeType
        description(
          name: "action:create_post",
          version: "1.0",
          defaults: {
            icon: "reply",
            color: "teal",
          },
          group: "discourse_actions",
          properties: {
            topic_id: {
              type: :string,
              required: true,
            },
            raw: {
              type: :string,
              required: true,
              ui: {
                control: :textarea,
              },
            },
            reply_to_post_number: {
              type: :integer,
              required: false,
            },
            author_username: {
              type: :string,
              required: false,
              default: "system",
              ui: {
                control: :user,
              },
            },
          },
          output_schema: {
            post: Schemas::Post.fields,
          },
        )

        def execute(exec_ctx)
          items =
            exec_ctx.input_items.map.with_index do |_item, item_index|
              config = {
                "topic_id" => exec_ctx.get_node_parameter("topic_id", item_index),
                "raw" => exec_ctx.get_node_parameter("raw", item_index),
                "reply_to_post_number" =>
                  exec_ctx.get_node_parameter("reply_to_post_number", item_index),
                "author_username" =>
                  exec_ctx.get_node_parameter("author_username", item_index, default: "system"),
              }

              wrap(process(exec_ctx, config))
            end

          [items]
        end

        private

        def process(exec_ctx, config)
          topic = ::Topic.find(config["topic_id"])
          if topic.closed? || topic.archived?
            raise ActiveRecord::RecordNotSaved,
                  I18n.t("discourse_workflows.errors.create_post.topic_closed_or_archived")
          end

          author = exec_ctx.find_user(username: config["author_username"].presence || "system")
          post_args = {
            topic_id: topic.id,
            raw: config["raw"],
            reply_to_post_number: config["reply_to_post_number"].presence,
            skip_workflows: true,
          }.compact
          post = PostCreator.new(author, post_args).create!

          { post: Schemas::Post.serialize(post) }
        end
      end
    end
  end
end
