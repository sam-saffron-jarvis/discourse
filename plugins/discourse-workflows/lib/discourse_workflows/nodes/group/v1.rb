# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Group
      class V1 < NodeType
        OPERATIONS = %w[add remove get].freeze

        description(
          name: "action:group",
          version: "1.0",
          defaults: {
            icon: "user-plus",
            color: "indigo",
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
            username: {
              type: :string,
              required: true,
              visible_if: {
                operation: %w[add remove],
              },
              ui: {
                control: :user,
              },
            },
            group_id: {
              type: :integer,
              required: true,
              options_source: "groups",
              ui: {
                control: :group_select,
              },
              control_options: {
                value_property: "id",
                name_property: "name",
                filterable: true,
                none: "discourse_workflows.group.group_id_placeholder",
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
            group: Schemas::Group.fields,
            user: {
              type: :object,
              fields: Schemas::User.fields,
              visible_if: {
                operation: %w[add remove],
              },
            },
          },
        )

        def self.load_options(context)
          context = DiscourseWorkflows::LoadOptionsContext.coerce(context)

          case context.source_key
          when "groups"
            scope = ::Group.order(:name)
            scope = scope.where(automatic: false) unless context.current_node_parameter(
              "operation",
            ) == "get"

            scope
              .pluck(:id, :name)
              .select { |_, name| context.matches_search?(name) }
              .map { |id, name| { id:, name: } }
          end
        end

        def execute(exec_ctx)
          map_input_items(exec_ctx) { |config| process(exec_ctx, config) }
        end

        private

        def process(exec_ctx, config)
          group = ::Group.find(config["group_id"])
          actor = exec_ctx.find_user(username: config["actor_username"].presence || "system")
          guardian = actor.guardian
          guardian.ensure_can_see_group!(group)
          group_data = Schemas::Group.serialize(group)

          return { group: group_data } if config["operation"] == "get"

          guardian.ensure_can_edit_group!(group)

          user = exec_ctx.find_user(username: config["username"])

          logger = GroupActionLogger.new(actor, group)

          case config["operation"]
          when "remove"
            group.remove(user)
            logger.log_remove_user_from_group(user)
          else
            group.add(user)
            logger.log_add_user_to_group(user)
          end

          { group: group_data, user: Schemas::User.serialize(user) }
        end
      end
    end
  end
end
