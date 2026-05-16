# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module PostCreated
      class V1 < NodeType
        description(
          name: "trigger:post_created",
          version: "1.0",
          defaults: {
            icon: "comment",
            color: "indigo",
          },
          group: "discourse_triggers",
          output_schema: {
            post: Schemas::Post.fields,
            topic: Schemas::Topic.fields,
          },
          events: [:post_created],
        )

        def initialize(post, opts = nil, *)
          super(parameters: {})
          @post = post
          @opts = opts
        end

        def valid?
          @post.present? && @post.topic.present? && @post.post_type == Post.types[:regular] &&
            !skip_workflows?(@opts)
        end

        def output
          { post: Schemas::Post.serialize(@post), topic: Schemas::Topic.serialize(@post.topic) }
        end
      end
    end
  end
end
