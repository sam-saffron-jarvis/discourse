# frozen_string_literal: true

if defined?(DiscourseWorkflows)
  module DiscourseWorkflows
    module Nodes
      module SendChatMessage
        class V1 < NodeType
          description(
            name: "action:send_chat_message",
            version: "1.0",
            defaults: {
              icon: "comment",
              color: "teal",
            },
            group: "discourse_actions",
            available: -> { SiteSetting.chat_enabled },
            unavailable_reason_key: "discourse_workflows.node_unavailable.requires_chat",
            properties: {
              channel_id: {
                type: :integer,
                required: true,
                type_options: {
                  load_options_method: "chat_channels",
                },
                no_data_expression: true,
                ui: {
                  control: :combo_box,
                },
                control_options: {
                  filterable: true,
                  value_property: :id,
                  name_property: :name,
                  set_from_option: {
                    channel_name: "name",
                  },
                },
              },
              channel_name: {
                type: :string,
                ui: {
                  hidden: true,
                },
              },
              message: {
                type: :string,
                required: true,
                ui: {
                  control: :textarea,
                },
              },
            },
            output_schema: {
              channel_id: :integer,
              message: :string,
            },
          )

          def self.load_options_context(context)
            case context.method_name
            when "chat_channels"
              ::Chat::Channel
                .public_channels
                .where(status: ::Chat::Channel.statuses[:open])
                .pluck(:id, :name, "categories.name")
                .map do |id, channel_name, category_name|
                  { id:, name: channel_name.presence || category_name }
                end
                .select { |channel| context.matches_filter?(channel[:name]) }
                .sort_by { |channel| channel[:name].downcase }
            end
          end

          def execute(exec_ctx)
            items =
              exec_ctx.input_items.map.with_index do |_item, item_index|
                config = {
                  "channel_id" => exec_ctx.get_node_parameter("channel_id", item_index),
                  "message" => exec_ctx.get_node_parameter("message", item_index),
                }
                result = process(config)
                wrap(result)
              end
            [items]
          end

          private

          def process(config)
            channel_id = config["channel_id"]
            message = config["message"]

            Chat::CreateMessage.call(
              guardian: Discourse.system_user.guardian,
              params: {
                chat_channel_id: channel_id,
                message: message,
              },
            ) do
              on_success { { "channel_id" => channel_id, "message" => message } }
              on_failed_contract do |contract|
                raise I18n.t(
                        "discourse_workflows.errors.send_chat_message.invalid_params",
                        errors: contract.errors.full_messages.join(", "),
                      )
              end
              on_model_not_found(:channel) do
                raise I18n.t(
                        "discourse_workflows.errors.send_chat_message.channel_not_found",
                        channel_id: channel_id,
                      )
              end
              on_failure { raise I18n.t("discourse_workflows.errors.send_chat_message.failed") }
            end
          end
        end
      end
    end
  end
end
