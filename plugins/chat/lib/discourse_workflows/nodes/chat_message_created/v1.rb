# frozen_string_literal: true

if defined?(DiscourseWorkflows)
  module DiscourseWorkflows
    module Nodes
      module ChatMessageCreated
        class V1 < NodeType
          description(
            name: "trigger:chat_message_created",
            version: "1.0",
            defaults: {
              icon: "comments",
              color: "teal",
            },
            group: "discourse_triggers",
            available: -> { SiteSetting.chat_enabled },
            unavailable_reason_key: "discourse_workflows.node_unavailable.requires_chat",
            properties: {
              channel_id: {
                type: :integer,
                required: false,
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
            },
            output_schema: {
              message: {
                type: :object,
                fields: {
                  id: :integer,
                  message: :string,
                  cooked: :string,
                  excerpt: :string,
                  created_at: :string,
                  thread_id: :integer,
                  chat_channel_id: :integer,
                },
              },
              channel: {
                type: :object,
                fields: {
                  id: :integer,
                  title: :string,
                  slug: :string,
                  chatable_type: :string,
                  chatable_id: :integer,
                },
              },
              user: Schemas::User.fields,
            },
          )

          def initialize(message, channel, user)
            super(parameters: {})
            @message = message
            @channel = channel
            @user = user
          end

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

          def valid?
            @message.present? && @channel.present?
          end

          def matches_node?(node)
            channel_id = NodeData.parameters(node)["channel_id"].presence
            channel_id.blank? || channel_id.to_i == @channel.id
          end

          def output
            {
              message: {
                id: @message.id,
                message: @message.message,
                cooked: @message.cooked,
                excerpt: @message.excerpt || @message.build_excerpt,
                created_at: @message.created_at.iso8601,
                thread_id: @message.thread_id,
                chat_channel_id: @message.chat_channel_id,
              },
              channel: {
                id: @channel.id,
                title: @channel.title(@user),
                slug: @channel.slug,
                chatable_type: @channel.chatable_type,
                chatable_id: @channel.chatable_id,
              },
              user: Schemas::User.serialize(@user),
            }
          end
        end
      end
    end
  end
end
