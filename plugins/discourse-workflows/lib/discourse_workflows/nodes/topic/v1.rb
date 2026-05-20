# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Topic
      class V1 < NodeType
        OPERATIONS = %w[create get list].freeze
        MAX_LIMIT = 100
        DEFAULT_LIMIT = 30

        description(
          name: "action:topic",
          version: "1.0",
          defaults: {
            icon: "comments",
            color: "light-blue",
          },
          group: "discourse_actions",
          properties: {
            operation: {
              type: :options,
              required: true,
              options: OPERATIONS,
              default: "create",
            },
            topic_id: {
              type: :string,
              required: true,
              visible_if: {
                operation: "get",
              },
            },
            title: {
              type: :string,
              required: true,
              visible_if: {
                operation: "create",
              },
            },
            raw: {
              type: :string,
              required: true,
              ui: {
                control: :textarea,
              },
              visible_if: {
                operation: "create",
              },
            },
            category_id: {
              type: :integer,
              required: false,
              ui: {
                control: :category,
              },
              visible_if: {
                operation: "create",
              },
            },
            tag_names: {
              type: :string,
              required: false,
              ui: {
                control: :tags,
              },
              visible_if: {
                operation: "create",
              },
            },
            query: {
              type: :string,
              required: true,
              ui: {
                control: :filter_query,
              },
              visible_if: {
                operation: "list",
              },
            },
            limit: {
              type: :integer,
              required: false,
              default: DEFAULT_LIMIT,
              visible_if: {
                operation: "list",
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
          output_schema: {
            topic: Schemas::Topic.fields,
            post_id: {
              type: :integer,
              visible_if: {
                operation: "create",
              },
            },
            post_number: {
              type: :integer,
              visible_if: {
                operation: "create",
              },
            },
          },
        )

        def execute(exec_ctx)
          items =
            exec_ctx.input_items.flat_map.with_index do |_item, item_index|
              config = {
                "operation" =>
                  exec_ctx.get_node_parameter("operation", item_index, default: "create"),
                "topic_id" => exec_ctx.get_node_parameter("topic_id", item_index),
                "title" => exec_ctx.get_node_parameter("title", item_index),
                "raw" => exec_ctx.get_node_parameter("raw", item_index),
                "category_id" => exec_ctx.get_node_parameter("category_id", item_index),
                "tag_names" => exec_ctx.get_node_parameter("tag_names", item_index),
                "query" => exec_ctx.get_node_parameter("query", item_index),
                "limit" => exec_ctx.get_node_parameter("limit", item_index, default: DEFAULT_LIMIT),
                "actor_username" =>
                  exec_ctx.get_node_parameter("actor_username", item_index, default: "system"),
              }

              Array.wrap(execute_with_config(exec_ctx, config))
            end

          [items]
        end

        private

        def execute_with_config(exec_ctx, config)
          case config["operation"]
          when "create"
            wrap(create_topic(exec_ctx, config))
          when "get"
            wrap(get_topic(exec_ctx, config))
          when "list"
            list_topics(exec_ctx, config).map { |data| wrap(data) }
          else
            raise ArgumentError,
                  I18n.t(
                    "discourse_workflows.errors.topic.unknown_operation",
                    operation: config["operation"],
                  )
          end
        end

        def create_topic(exec_ctx, config)
          author = exec_ctx.find_user(username: config["actor_username"].presence || "system")
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
            on_failure { raise I18n.t("discourse_workflows.errors.topic.create_failed") }
          end
        end

        def get_topic(exec_ctx, config)
          topic = ::Topic.find(config["topic_id"])
          actor = exec_ctx.find_user(username: config["actor_username"].presence || "system")
          actor.guardian.ensure_can_see!(topic)
          { topic: Schemas::Topic.serialize(topic) }
        end

        def list_topics(exec_ctx, config)
          limit = [[Integer(config["limit"] || DEFAULT_LIMIT), 1].max, MAX_LIMIT].min
          actor = exec_ctx.find_user(username: config["actor_username"].presence || "system")
          topic_query = TopicQuery.new(actor, q: config["query"], per_page: limit)
          topic_list = topic_query.list_filter

          posts = topic_list.topics.map(&:first_post).compact
          if posts.any?
            ActiveRecord::Associations::Preloader.new(records: posts, associations: :user).call
          end

          topic_list.topics.map { |topic| { topic: Schemas::Topic.serialize(topic) } }
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
