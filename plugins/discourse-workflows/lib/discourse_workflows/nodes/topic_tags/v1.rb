# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module TopicTags
      class V1 < NodeType
        OPERATIONS = %w[add remove].freeze

        description(
          name: "action:topic_tags",
          version: "1.0",
          defaults: {
            icon: "tags",
            color: "orange",
          },
          group: "discourse_actions",
          properties: {
            operation: {
              type: :options,
              required: true,
              options: OPERATIONS,
              default: "add",
              ui: {
                expression: true,
              },
            },
            topic_id: {
              type: :string,
              required: true,
            },
            tag_names: {
              type: :string,
              required: false,
              ui: {
                control: :tags,
              },
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
        )

        def execute(exec_ctx)
          map_input_items(exec_ctx) { |config| process(exec_ctx, config) }
        end

        private

        def process(exec_ctx, config)
          topic = Topic.find(config["topic_id"])
          actor = exec_ctx.find_user(username: config["actor_username"].presence || "system")
          guardian = actor.guardian

          names =
            Array
              .wrap(config["tag_names"])
              .flat_map { |n| n.to_s.split(",") }
              .filter_map { |n| n.strip.presence }
          raise I18n.t("discourse_workflows.errors.topic_tags.no_tag_names") if names.empty?

          case config["operation"]
          when "remove"
            old_tag_names = topic.tags.pluck(:name)
            desired_tag_names = old_tag_names - names
            tag_topic!(topic, guardian, desired_tag_names)
            { tag_names: old_tag_names & names, topic_id: topic.id }
          else
            tag_topic!(topic, guardian, names, append: true)
            { tag_names: names, topic_id: topic.id }
          end
        end

        def tag_topic!(topic, guardian, tag_names, append: false)
          unless DiscourseTagging.tag_topic_by_names(topic, guardian, tag_names, append:)
            raise I18n.t(
                    "discourse_workflows.errors.topic_tags.operation_failed",
                    errors: topic.errors.full_messages.join(", "),
                  )
          end
          topic.save!
        end
      end
    end
  end
end
