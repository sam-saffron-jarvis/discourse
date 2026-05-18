# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module ListTopics
      class V1 < NodeType
        MAX_LIMIT = 100
        DEFAULT_LIMIT = 30

        description(
          name: "action:list_topics",
          version: "1.0",
          defaults: {
            icon: "list",
            color: "light-blue",
          },
          group: "discourse_actions",
          properties: {
            query: {
              type: :string,
              required: true,
              ui: {
                control: :filter_query,
              },
            },
            limit: {
              type: :integer,
              required: false,
              default: DEFAULT_LIMIT,
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
          query = exec_ctx.get_node_parameter("query", 0)
          raw_limit = exec_ctx.get_node_parameter("limit", 0, default: DEFAULT_LIMIT)
          limit = [[Integer(raw_limit), 1].max, MAX_LIMIT].min

          actor_username = exec_ctx.get_node_parameter("actor_username", 0, default: "system")
          actor = exec_ctx.find_user(username: actor_username.presence || "system")
          topic_query = TopicQuery.new(actor, q: query, per_page: limit)
          topic_list = topic_query.list_filter

          posts = topic_list.topics.map(&:first_post).compact
          if posts.any?
            ActiveRecord::Associations::Preloader.new(records: posts, associations: :user).call
          end

          items =
            topic_list.topics.map { |topic| wrap({ "topic" => Schemas::Topic.serialize(topic) }) }
          [items]
        end
      end
    end
  end
end
