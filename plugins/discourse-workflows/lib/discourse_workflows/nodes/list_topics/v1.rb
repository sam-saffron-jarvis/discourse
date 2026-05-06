# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module ListTopics
      class V1 < NodeType
        MAX_LIMIT = 100
        DEFAULT_LIMIT = 30

        def self.identifier
          "action:list_topics"
        end

        def self.icon
          "list"
        end

        def self.color
          "light-blue"
        end

        def self.group
          "discourse_actions"
        end

        def self.property_schema
          {
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
          }
        end

        def self.output_schema
          { topic: Schemas::Topic.fields }
        end

        def execute(exec_ctx)
          item = exec_ctx.input_items.first || { "json" => {} }
          config = exec_ctx.get_parameters(item)

          query = config["query"]
          limit = [[Integer(config.fetch("limit") { DEFAULT_LIMIT }), 1].max, MAX_LIMIT].min

          actor = exec_ctx.find_user(username: config["actor_username"].presence || "system")
          topic_query = TopicQuery.new(actor, q: query, per_page: limit)
          topic_list = topic_query.list_filter

          posts = topic_list.topics.map(&:first_post).compact
          if posts.any?
            ActiveRecord::Associations::Preloader.new(records: posts, associations: :user).call
          end

          items = topic_list.topics.map { |topic| wrap(topic: Schemas::Topic.resolve(topic)) }
          [items]
        end
      end
    end
  end
end
