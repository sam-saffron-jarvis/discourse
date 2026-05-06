# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module CreatePost
      class V1 < NodeType
        def self.identifier
          "action:create_post"
        end

        def self.icon
          "reply"
        end

        def self.color
          "teal"
        end

        def self.group
          "discourse_actions"
        end

        def self.property_schema
          {
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
          }
        end

        def self.output_schema
          { post: Schemas::Post.fields }
        end

        def execute(exec_ctx)
          items =
            exec_ctx.input_items.map do |item|
              config = exec_ctx.get_parameters(item)
              result = process(exec_ctx, config)
              wrap(result)
            end
          [items]
        end

        private

        def process(exec_ctx, config)
          topic = Topic.find(config["topic_id"])
          ensure_topic_is_open!(topic)

          author = exec_ctx.find_user(username: config["author_username"].presence || "system")
          post = PostCreator.new(author, build_post_args(topic, config)).create!

          { post: Schemas::Post.resolve(post) }
        end

        def ensure_topic_is_open!(topic)
          return unless topic.closed? || topic.archived?
          raise ActiveRecord::RecordNotSaved,
                I18n.t("discourse_workflows.errors.create_post.topic_closed_or_archived")
        end

        def build_post_args(topic, config)
          {
            topic_id: topic.id,
            raw: config["raw"],
            reply_to_post_number: config["reply_to_post_number"].presence,
          }.compact
        end
      end
    end
  end
end
