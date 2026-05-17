# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module CreateTopic
      class V1 < NodeType
        description(
          name: "action:create_topic",
          version: "1.0",
          defaults: {
            icon: "plus",
            color: "light-green",
          },
          group: "discourse_actions",
          properties: {
            title: {
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
            category_id: {
              type: :integer,
              required: false,
              ui: {
                control: :category,
              },
            },
            tag_names: {
              type: :string,
              required: false,
              ui: {
                control: :tags,
              },
            },
            username: {
              type: :string,
              required: true,
              default: "system",
              ui: {
                control: :user,
              },
            },
          },
          output_schema: {
            topic: Schemas::Topic.fields,
            post_id: :integer,
            post_number: :integer,
          },
        )

        def execute(exec_ctx)
          map_input_items(exec_ctx) { |config| process(exec_ctx, config) }
        end

        private

        def process(exec_ctx, config)
          author = exec_ctx.find_user(username: config["username"])
          tag_names = normalize_tag_names(config["tag_names"])

          DiscourseTools::CreateTopic.call(
            params: {
              title: config["title"],
              raw: config["raw"],
              category_id: (config["category_id"].presence&.to_i),
            },
            options: {
              tags: tag_names.presence,
              skip_workflows: true,
            },
            guardian: author.guardian,
          ) do
            on_success do |post:|
              topic = post.topic
              {
                topic: Schemas::Topic.serialize(topic),
                post_id: post.id,
                post_number: post.post_number,
              }
            end
            on_failed_step(:create_post) { |step| raise step.error }
            on_failure { raise I18n.t("discourse_workflows.errors.create_topic.failed") }
          end
        end

        def normalize_tag_names(tag_names)
          Array
            .wrap(tag_names)
            .flat_map { |name| name.to_s.split(",") }
            .filter_map { |name| name.strip.presence }
        end
      end
    end
  end
end
