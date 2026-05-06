# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Badge
      class V1 < NodeType
        OPERATIONS = %w[grant revoke].freeze

        def self.identifier
          "action:badge"
        end

        def self.icon
          "certificate"
        end

        def self.color
          "yellow"
        end

        def self.group
          "discourse_actions"
        end

        def self.property_schema
          {
            operation: {
              type: :options,
              required: true,
              options: OPERATIONS,
              default: "grant",
              ui: {
                expression: true,
              },
            },
            username: {
              type: :string,
              required: true,
              ui: {
                control: :user,
              },
            },
            badge_id: {
              type: :integer,
              required: true,
              options_source: "badges",
              ui: {
                control: :combo_box,
              },
              control_options: {
                value_property: "id",
                name_property: "name",
                filterable: true,
                none: "discourse_workflows.badge.badge_id_placeholder",
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
          }
        end

        def self.load_options(source_key)
          case source_key
          when "badges"
            ::Badge
              .where(enabled: true)
              .order(:name)
              .pluck(:id, :name)
              .map { |id, name| { id:, name: } }
          end
        end

        def self.output_schema
          { user_id: :integer, username: :string, badge_id: :integer, badge_name: :string }
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
          user = exec_ctx.find_user(username: config["username"])
          badge = ::Badge.find(config["badge_id"])
          actor = exec_ctx.find_user(username: config["actor_username"].presence || "system")

          case config["operation"]
          when "revoke"
            user_badge = UserBadge.find_by(user: user, badge: badge)
            BadgeGranter.revoke(user_badge, revoked_by: actor) if user_badge
          else
            BadgeGranter.grant(badge, user, granted_by: actor)
          end

          { user_id: user.id, username: user.username, badge_id: badge.id, badge_name: badge.name }
        end
      end
    end
  end
end
