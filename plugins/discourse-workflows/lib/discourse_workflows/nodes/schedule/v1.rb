# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Schedule
      class V1 < NodeType
        HOUR_OPTIONS = (0..23).to_a.freeze
        WEEKDAY_OPTIONS = [1, 2, 3, 4, 5, 6, 0].freeze

        description(
          name: "trigger:schedule",
          version: "1.0",
          defaults: {
            icon: "calendar-days",
            color: "orange",
          },
          properties: {
            rule: {
              type: :fixed_collection,
              required: true,
              type_options: {
                multiple_values: true,
              },
              ui: {
                flat: true,
              },
              options: [
                {
                  name: "interval",
                  values: {
                    field: {
                      type: :options,
                      required: true,
                      default: "days",
                      options: %w[minutes hours days weeks months cronExpression],
                      no_data_expression: true,
                    },
                    minutesInterval: {
                      type: :integer,
                      default: 5,
                      min: 1,
                      max: 59,
                      visible_if: {
                        field: %w[minutes],
                      },
                      no_data_expression: true,
                    },
                    hoursInterval: {
                      type: :integer,
                      default: 1,
                      min: 1,
                      max: 23,
                      visible_if: {
                        field: %w[hours],
                      },
                      no_data_expression: true,
                    },
                    daysInterval: {
                      type: :integer,
                      default: 1,
                      min: 1,
                      max: 31,
                      visible_if: {
                        field: %w[days],
                      },
                      no_data_expression: true,
                    },
                    weeksInterval: {
                      type: :integer,
                      default: 1,
                      min: 1,
                      max: 52,
                      visible_if: {
                        field: %w[weeks],
                      },
                      no_data_expression: true,
                    },
                    monthsInterval: {
                      type: :integer,
                      default: 1,
                      min: 1,
                      max: 12,
                      visible_if: {
                        field: %w[months],
                      },
                      no_data_expression: true,
                    },
                    triggerAtDay: {
                      type: :multi_options,
                      default: [0],
                      options: WEEKDAY_OPTIONS,
                      visible_if: {
                        field: %w[weeks],
                      },
                      control_options: {
                        option_format: :weekday,
                      },
                    },
                    triggerAtDayOfMonth: {
                      type: :integer,
                      default: 1,
                      min: 1,
                      max: 31,
                      visible_if: {
                        field: %w[months],
                      },
                      no_data_expression: true,
                    },
                    triggerAtHour: {
                      type: :options,
                      default: 0,
                      options: HOUR_OPTIONS,
                      visible_if: {
                        field: %w[days weeks months],
                      },
                      no_data_expression: true,
                      ui: {
                        control: :combo_box,
                      },
                      control_options: {
                        option_format: :hour_of_day,
                      },
                    },
                    triggerAtMinute: {
                      type: :integer,
                      default: 0,
                      min: 0,
                      max: 59,
                      visible_if: {
                        field: %w[hours days weeks months],
                      },
                      no_data_expression: true,
                    },
                    expression: {
                      type: :string,
                      validate: :cron,
                      visible_if: {
                        field: %w[cronExpression],
                      },
                    },
                  },
                },
              ],
            },
          },
          output_schema: {
            timestamp: :string,
            "Readable date": :string,
            "Readable time": :string,
            "Day of week": :string,
            Year: :string,
            Month: :string,
            "Day of month": :string,
            Hour: :string,
            Minute: :string,
            Second: :string,
            Timezone: :string,
          },
          capabilities: {
            manually_triggerable: true,
          },
        )

        def initialize(*)
          super(parameters: {})
        end

        def self.validate_configuration(configuration, errors)
          Rules.validate_configuration(configuration, errors)
        end

        def trigger(trigger_ctx)
          rules = Rules.from_rule_parameter(trigger_ctx.get_node_parameter("rule", {}))
          node_key = "#{trigger_ctx.workflow_id}:#{trigger_ctx.node_id}"
          schedules =
            rules.map.with_index do |rule, index|
              {
                rule: rule,
                rule_index: index,
                cron_expression: Rules.to_cron_expression(rule, node_key),
                recurrence: Rules.recurrence(rule, index),
              }
            end

          if trigger_ctx.get_mode == "manual"
            return(
              {
                manual_trigger_function:
                  lambda do
                    schedule = schedules.first
                    if schedule
                      execute_trigger(
                        trigger_ctx,
                        schedule[:recurrence],
                        rule_index: schedule[:rule_index],
                        skip_recurrence_check: true,
                        deduplicate: false,
                      )
                    end
                  end,
              }
            )
          end

          schedules.each do |schedule|
            trigger_ctx
              .helpers
              .register_cron(
                { expression: schedule[:cron_expression], recurrence: schedule[:recurrence] },
              ) do |scheduled_time|
                execute_trigger(
                  trigger_ctx,
                  schedule[:recurrence],
                  rule_index: schedule[:rule_index],
                  scheduled_time:,
                )
              end
          end

          {}
        end

        def output(time: Time.current, timezone: DiscourseWorkflows::WorkflowTimezone.default)
          Payload.build(time:, timezone:)
        end

        private

        def execute_trigger(
          trigger_ctx,
          recurrence,
          rule_index:,
          scheduled_time: Time.current.utc,
          skip_recurrence_check: false,
          deduplicate: true
        )
          timezone = trigger_ctx.get_timezone
          static_data = trigger_ctx.get_workflow_static_data(:node)
          recurrence_rules = static_data["recurrenceRules"] ||= []
          if !skip_recurrence_check &&
               !Recurrence.due?(recurrence, recurrence_rules, scheduled_time, timezone)
            return
          end

          trigger_ctx.emit(
            [
              trigger_ctx.helpers.return_json_array(
                [Payload.build(time: scheduled_time, timezone:)],
              ),
            ],
            deduplication_key:
              (
                if deduplicate
                  "#{trigger_ctx.workflow_id}:#{trigger_ctx.node_id}:#{rule_index}:#{scheduled_time.utc.iso8601}"
                end
              ),
          )
        end
      end
    end
  end
end
