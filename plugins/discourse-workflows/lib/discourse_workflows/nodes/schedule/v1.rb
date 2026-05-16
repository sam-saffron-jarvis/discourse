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
            rules: {
              type: :fixed_collection,
              required: true,
              max_items: ScheduleRule::MAX_RULES_PER_NODE,
              type_options: {
                multiple_values: true,
              },
              ui: {
                flat: true,
              },
              options: [
                {
                  name: "values",
                  values: {
                    interval: {
                      type: :options,
                      required: true,
                      default: "days",
                      options: %w[seconds minutes hours days weeks months cron],
                      ui: {
                        expression: false,
                      },
                    },
                    seconds_between_triggers: {
                      type: :integer,
                      default: 30,
                      min: 1,
                      max: 59,
                      visible_if: {
                        interval: %w[seconds],
                      },
                      ui: {
                        expression: false,
                      },
                    },
                    minutes_between_triggers: {
                      type: :integer,
                      default: 5,
                      min: 1,
                      max: 59,
                      visible_if: {
                        interval: %w[minutes],
                      },
                      ui: {
                        expression: false,
                      },
                    },
                    hours_between_triggers: {
                      type: :integer,
                      default: 1,
                      min: 1,
                      max: 23,
                      visible_if: {
                        interval: %w[hours],
                      },
                      ui: {
                        expression: false,
                      },
                    },
                    days_between_triggers: {
                      type: :integer,
                      default: 1,
                      min: 1,
                      max: 31,
                      visible_if: {
                        interval: %w[days],
                      },
                      ui: {
                        expression: false,
                      },
                    },
                    weeks_between_triggers: {
                      type: :integer,
                      default: 1,
                      min: 1,
                      max: 52,
                      visible_if: {
                        interval: %w[weeks],
                      },
                      ui: {
                        expression: false,
                      },
                    },
                    months_between_triggers: {
                      type: :integer,
                      default: 1,
                      min: 1,
                      max: 12,
                      visible_if: {
                        interval: %w[months],
                      },
                      ui: {
                        expression: false,
                      },
                    },
                    trigger_on_weekdays: {
                      type: :multi_options,
                      default: [0],
                      options: WEEKDAY_OPTIONS,
                      visible_if: {
                        interval: %w[weeks],
                      },
                      control_options: {
                        option_format: :weekday,
                      },
                    },
                    trigger_at_day_of_month: {
                      type: :integer,
                      default: 1,
                      min: 1,
                      max: 31,
                      visible_if: {
                        interval: %w[months],
                      },
                      ui: {
                        expression: false,
                      },
                    },
                    trigger_at_hour: {
                      type: :options,
                      default: 0,
                      options: HOUR_OPTIONS,
                      visible_if: {
                        interval: %w[days weeks months],
                      },
                      ui: {
                        control: :combo_box,
                        expression: false,
                      },
                      control_options: {
                        option_format: :hour_of_day,
                      },
                    },
                    trigger_at_minute: {
                      type: :integer,
                      default: 0,
                      min: 0,
                      max: 59,
                      visible_if: {
                        interval: %w[hours days weeks months],
                      },
                      ui: {
                        expression: false,
                      },
                    },
                    cron: {
                      type: :string,
                      validate: :cron,
                      visible_if: {
                        interval: %w[cron],
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
          configuration = configuration.is_a?(Hash) ? configuration.with_indifferent_access : {}
          rules = ScheduleRule.rules_from_configuration(configuration)

          if rules.empty?
            errors.add(:base, I18n.t("discourse_workflows.errors.schedule_rules_required"))
            return
          end

          if rules.size > ScheduleRule::MAX_RULES_PER_NODE
            errors.add(
              :base,
              I18n.t(
                "discourse_workflows.errors.too_many_schedule_rules",
                count: ScheduleRule::MAX_RULES_PER_NODE,
              ),
            )
            return
          end

          rules.each do |rule|
            next if ScheduleRule.valid_rule?(rule)

            errors.add(:base, I18n.t("discourse_workflows.errors.invalid_schedule_rule"))
            break
          end
        end

        def output(time: Time.current, timezone: ScheduleRule.default_timezone)
          local_time = time.in_time_zone(timezone)
          hour = local_time.hour % 12
          hour = 12 if hour.zero?
          readable_time = "#{hour}:#{local_time.strftime("%M:%S %P")}"

          {
            timestamp: local_time.iso8601(3),
            "Readable date":
              "#{local_time.strftime("%B")} #{local_time.day.ordinalize} #{local_time.year}, #{readable_time}",
            "Readable time": readable_time,
            "Day of week": local_time.strftime("%A"),
            Year: local_time.strftime("%Y"),
            Month: local_time.strftime("%B"),
            "Day of month": local_time.strftime("%d"),
            Hour: local_time.strftime("%H"),
            Minute: local_time.strftime("%M"),
            Second: local_time.strftime("%S"),
            Timezone: "#{timezone} (UTC#{local_time.formatted_offset})",
          }
        end
      end
    end
  end
end
