# frozen_string_literal: true

module DiscourseWorkflows
  module TriggerTracking
    module_function

    def triggered_this_minute?(workflow, node_id, now = Time.current.utc)
      data = workflow.node_static_data(node_id)
      last_triggered = data["last_triggered_at"]
      return false unless last_triggered
      Time.parse(last_triggered).beginning_of_minute == now.beginning_of_minute
    end

    def mark_triggered!(workflow, node_id, now = Time.current.utc)
      data = workflow.node_static_data(node_id)
      workflow.update_node_static_data!(node_id, data.merge("last_triggered_at" => now.iso8601))
    end

    def triggered_topic_ids(workflow, node_id)
      workflow.node_static_data(node_id).fetch("triggered_topic_ids", [])
    end

    def replace_triggered_topic_ids!(workflow, node_id, topic_ids)
      workflow.reload
      data = workflow.node_static_data(node_id)
      workflow.update_node_static_data!(node_id, data.merge("triggered_topic_ids" => topic_ids))
    end

    def collect_stale_topics!(workflow, node, max_topics:)
      hours = (node.dig("configuration", "hours") || 24).to_i.clamp(1..)
      threshold = hours.hours.ago
      tracked_ids = triggered_topic_ids(workflow, node["id"])

      stale_scope =
        Topic
          .where("GREATEST(topics.created_at, topics.last_posted_at) < ?", threshold)
          .where(closed: false, archived: false, deleted_at: nil, visible: true)
          .where("topics.archetype = ?", Archetype.default)

      newly_stale =
        stale_scope.where.not(id: tracked_ids).includes(first_post: :user).limit(max_topics).to_a

      still_tracked = tracked_ids.any? ? stale_scope.where(id: tracked_ids).pluck(:id) : []

      replace_triggered_topic_ids!(workflow, node["id"], still_tracked + newly_stale.map(&:id))

      newly_stale
    end
  end
end
