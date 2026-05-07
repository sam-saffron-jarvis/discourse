# frozen_string_literal: true

if defined?(DiscourseWorkflows)
  module DiscourseWorkflows
    module Nodes
      module AssignTopic
        class V1 < NodeType
          OPERATIONS = %w[assign unassign].freeze

          extend_schema :topic,
                        fields: {
                          assigned_to: :string,
                        },
                        serializer: ->(topic) do
                          assignment = Assignment.find_by(target: topic)
                          { assigned_to: assignment&.assigned_to&.display_name }
                        end

          def self.identifier
            "action:assign_topic"
          end

          def self.icon
            "user-plus"
          end

          def self.color
            "cyan"
          end

          def self.available?
            SiteSetting.assign_enabled
          end

          def self.unavailable_reason_key
            "discourse_workflows.node_unavailable.requires_assign"
          end

          def self.property_schema
            {
              operation: {
                type: :options,
                required: true,
                options: OPERATIONS,
                default: "assign",
                ui: {
                  expression: true,
                },
              },
              topic_id: {
                type: :string,
                required: true,
              },
              assignee: {
                type: :string,
                required: true,
                visible_if: {
                  operation: "assign",
                },
                ui: {
                  control: :user_or_group,
                },
              },
              replace_existing: {
                type: :boolean,
                default: true,
                visible_if: {
                  operation: "assign",
                },
              },
            }
          end

          def self.output_schema
            {
              assignee: {
                type: :object,
                fields: DiscourseWorkflows::Schemas::Assignee.fields,
                visible_if: {
                  operation: "assign",
                },
              },
              previously_assigned: {
                type: :object,
                fields: DiscourseWorkflows::Schemas::Assignee.fields,
              },
            }
          end

          def execute(exec_ctx)
            actor = exec_ctx.user
            items =
              exec_ctx.input_items.map do |item|
                config = exec_ctx.get_parameters(item)
                result = process(actor, config)
                wrap(result)
              end
            [items]
          end

          private

          def process(actor, config)
            topic = Topic.find(config["topic_id"])
            assigner = ::Assigner.new(topic, actor)
            previously_assigned = topic.assignment&.assigned_to

            case config["operation"]
            when "unassign"
              assigner.unassign

              {
                previously_assigned:
                  DiscourseWorkflows::Schemas::Assignee.serialize(previously_assigned),
              }
            else
              assignee = find_assignee(config["assignee"])
              assigner.unassign if config["replace_existing"] != false && topic.assignment

              result = assigner.assign(assignee)

              unless result[:success]
                raise I18n.t(
                        "discourse_assign.discourse_workflows.assign_topic.error",
                        reason: result[:reason],
                      )
              end

              {
                assignee: DiscourseWorkflows::Schemas::Assignee.serialize(assignee),
                previously_assigned:
                  DiscourseWorkflows::Schemas::Assignee.serialize(previously_assigned),
              }
            end
          end

          def find_assignee(identifier)
            User.find_by(username: identifier) || ::Group.find_by!(name: identifier)
          end
        end
      end
    end
  end
end
