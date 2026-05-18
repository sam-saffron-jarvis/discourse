# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Badge
      class V1 < NodeType
        OPERATIONS = %w[grant revoke].freeze

        description(
          name: "action:badge",
          version: "1.0",
          defaults: {
            icon: "certificate",
            color: "yellow",
          },
          group: "discourse_actions",
          properties: {
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
              type_options: {
                load_options_method: "badges",
              },
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
          },
          output_schema: {
            user_id: :integer,
            username: :string,
            badge_id: :integer,
            badge_name: :string,
          },
        )

        def self.load_options_context(context)
          case context.method_name
          when "badges"
            ::Badge
              .where(enabled: true)
              .order(:name)
              .pluck(:id, :name)
              .select { |_, name| context.matches_filter?(name) }
              .map { |id, name| { id:, name: } }
          end
        end

        def execute(exec_ctx)
          map_input_items(exec_ctx) { |config| process(exec_ctx, config) }
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
