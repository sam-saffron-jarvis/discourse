# frozen_string_literal: true

if defined?(DiscourseWorkflows)
  module DiscourseWorkflows
    module Nodes
      module SendChatMessage
        class V1 < NodeType
          def self.identifier
            "action:send_chat_message"
          end

          def self.icon
            "comment"
          end

          def self.color
            "teal"
          end

          def self.available?
            SiteSetting.chat_enabled
          end

          def self.group
            "discourse_actions"
          end

          def self.unavailable_reason_key
            "discourse_workflows.node_unavailable.requires_chat"
          end

          def self.output_schema
            { channel_id: :integer, message: :string }
          end

          def self.property_schema
            {
              channel_id: {
                type: :integer,
                required: true,
              },
              message: {
                type: :string,
                required: true,
                ui: {
                  control: :textarea,
                },
              },
            }
          end

          def execute(exec_ctx)
            items =
              exec_ctx.input_items.map do |item|
                config = exec_ctx.get_node_parameters(item)
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
