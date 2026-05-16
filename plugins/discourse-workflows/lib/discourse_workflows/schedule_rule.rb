# frozen_string_literal: true

require "digest"

module DiscourseWorkflows
  module ScheduleRule
    module_function

    VALID_INTERVALS = %w[seconds minutes hours days weeks months cron cronExpression].freeze
    DEFAULT_TIMEZONE = "UTC"
    RECURRENCE_RULES_KEY = "recurrence_rules"
    TRIGGERED_OCCURRENCES_KEY = "triggered_occurrences"
    MAX_TRIGGERED_OCCURRENCES = 200

    MAX_RULES_PER_NODE = 5

    class Rule
      attr_reader :data

      def initialize(raw)
        @data = raw.is_a?(Hash) ? raw.with_indifferent_access : raw
      end

      def interval
        @data[:interval] || @data[:field]
      end

      def cron
        @data[:cron] || @data[:expression]
      end

      def [](key)
        @data[key]
      end

      def fetch(key, *args, &block)
        @data.fetch(key, *args, &block)
      end

      def handler
        INTERVAL_HANDLERS.fetch(interval)
      end
    end

    module IntervalHandler
      class Seconds
        def to_cron_expression(rule, _node_key)
          n = (rule[:seconds_between_triggers] || 30).to_i.clamp(1, 59)
          "*/#{n} * * * * *"
        end

        def valid?(rule)
          n = (rule[:seconds_between_triggers] || 30).to_i
          n >= 1 && n <= 59
        end

        def recurrence(_rule, _index) = ScheduleRule.inactive_recurrence
      end

      class Minutes
        def to_cron_expression(rule, node_key)
          n = (rule[:minutes_between_triggers] || 5).to_i.clamp(1, 59)
          second = ScheduleRule.stable_int(node_key, "second", 0, 60)
          "#{second} */#{n} * * * *"
        end

        def valid?(rule)
          n = rule[:minutes_between_triggers]
          n.nil? || n.to_i.between?(1, 59)
        end

        def recurrence(_rule, _index) = ScheduleRule.inactive_recurrence
      end

      class Hours
        def to_cron_expression(rule, node_key)
          n = (rule[:hours_between_triggers] || 1).to_i.clamp(1, 23)
          second = ScheduleRule.stable_int(node_key, "second", 0, 60)
          minute =
            (
              if rule[:trigger_at_minute].nil?
                ScheduleRule.stable_int(node_key, "minute", 0, 60)
              else
                rule[:trigger_at_minute].to_i.clamp(0, 59)
              end
            )

          return "#{second} #{minute} */#{n} * * *" if (24 % n).zero?

          "#{second} #{minute} * * * *"
        end

        def valid?(rule)
          n = rule[:hours_between_triggers]
          m = rule[:trigger_at_minute]
          (n.nil? || n.to_i.between?(1, 23)) && (m.nil? || m.to_i.between?(0, 59))
        end

        def recurrence(rule, index)
          ScheduleRule.recurrence_for(
            interval_size: (rule[:hours_between_triggers] || 1).to_i,
            index:,
            type_interval: "hours",
          )
        end
      end

      class Days
        def to_cron_expression(rule, node_key)
          n = (rule[:days_between_triggers] || 1).to_i.clamp(1, 31)
          second = ScheduleRule.stable_int(node_key, "second", 0, 60)
          minute =
            (
              if rule[:trigger_at_minute].nil?
                ScheduleRule.stable_int(node_key, "minute", 0, 60)
              else
                rule[:trigger_at_minute].to_i.clamp(0, 59)
              end
            )
          hour =
            (
              if rule[:trigger_at_hour].nil?
                ScheduleRule.stable_int(node_key, "hour", 0, 24)
              else
                rule[:trigger_at_hour].to_i.clamp(0, 23)
              end
            )

          "#{second} #{minute} #{hour} * * *"
        end

        def valid?(rule)
          n = rule[:days_between_triggers]
          h = rule[:trigger_at_hour]
          m = rule[:trigger_at_minute]
          (n.nil? || n.to_i.between?(1, 31)) && (h.nil? || h.to_i.between?(0, 23)) &&
            (m.nil? || m.to_i.between?(0, 59))
        end

        def recurrence(rule, index)
          ScheduleRule.recurrence_for(
            interval_size: (rule[:days_between_triggers] || 1).to_i,
            index:,
            type_interval: "days",
          )
        end
      end

      class Weeks
        def to_cron_expression(rule, node_key)
          second = ScheduleRule.stable_int(node_key, "second", 0, 60)
          minute =
            (
              if rule[:trigger_at_minute].nil?
                ScheduleRule.stable_int(node_key, "minute", 0, 60)
              else
                rule[:trigger_at_minute].to_i.clamp(0, 59)
              end
            )
          hour =
            (
              if rule[:trigger_at_hour].nil?
                ScheduleRule.stable_int(node_key, "hour", 0, 24)
              else
                rule[:trigger_at_hour].to_i.clamp(0, 23)
              end
            )
          weekdays = Array.wrap(rule[:trigger_on_weekdays]).map(&:to_i)
          days_of_week = weekdays.empty? ? "*" : weekdays.join(",")

          "#{second} #{minute} #{hour} * * #{days_of_week}"
        end

        def valid?(rule)
          n = rule[:weeks_between_triggers]
          h = rule[:trigger_at_hour]
          m = rule[:trigger_at_minute]
          days = rule[:trigger_on_weekdays]
          (n.nil? || n.to_i.between?(1, 52)) && (h.nil? || h.to_i.between?(0, 23)) &&
            (m.nil? || m.to_i.between?(0, 59)) &&
            (days.blank? || Array.wrap(days).all? { |d| d.to_i.between?(0, 6) })
        end

        def recurrence(rule, index)
          ScheduleRule.recurrence_for(
            interval_size: (rule[:weeks_between_triggers] || 1).to_i,
            index:,
            type_interval: "weeks",
          )
        end
      end

      class Months
        def to_cron_expression(rule, node_key)
          n = (rule[:months_between_triggers] || 1).to_i.clamp(1, 12)
          second = ScheduleRule.stable_int(node_key, "second", 0, 60)
          minute =
            (
              if rule[:trigger_at_minute].nil?
                ScheduleRule.stable_int(node_key, "minute", 0, 60)
              else
                rule[:trigger_at_minute].to_i.clamp(0, 59)
              end
            )
          hour =
            (
              if rule[:trigger_at_hour].nil?
                ScheduleRule.stable_int(node_key, "hour", 0, 24)
              else
                rule[:trigger_at_hour].to_i.clamp(0, 23)
              end
            )
          day =
            (
              if rule[:trigger_at_day_of_month].nil?
                ScheduleRule.stable_int(node_key, "dayOfMonth", 1, 29)
              else
                rule[:trigger_at_day_of_month].to_i.clamp(1, 31)
              end
            )

          "#{second} #{minute} #{hour} #{day} */#{n} *"
        end

        def valid?(rule)
          n = rule[:months_between_triggers]
          d = rule[:trigger_at_day_of_month]
          h = rule[:trigger_at_hour]
          m = rule[:trigger_at_minute]
          (n.nil? || n.to_i.between?(1, 12)) && (d.nil? || d.to_i.between?(1, 31)) &&
            (h.nil? || h.to_i.between?(0, 23)) && (m.nil? || m.to_i.between?(0, 59))
        end

        def recurrence(rule, index)
          ScheduleRule.recurrence_for(
            interval_size: (rule[:months_between_triggers] || 1).to_i,
            index:,
            type_interval: "months",
          )
        end
      end

      class Cron
        def to_cron_expression(rule, _node_key) = rule.cron

        def valid?(rule) = CronParser.valid?(rule.cron)

        def recurrence(_rule, _index) = ScheduleRule.inactive_recurrence
      end
    end

    INTERVAL_HANDLERS = {
      "seconds" => IntervalHandler::Seconds.new,
      "minutes" => IntervalHandler::Minutes.new,
      "hours" => IntervalHandler::Hours.new,
      "days" => IntervalHandler::Days.new,
      "weeks" => IntervalHandler::Weeks.new,
      "months" => IntervalHandler::Months.new,
      "cron" => IntervalHandler::Cron.new,
      "cronExpression" => IntervalHandler::Cron.new,
    }.freeze

    def wrap(rule)
      rule.is_a?(Rule) ? rule : Rule.new(rule)
    end

    def to_cron_expression(rule, node_key = "")
      rule = wrap(rule)
      rule.handler.to_cron_expression(rule, node_key)
    end

    def recurrence(rule, index)
      rule = wrap(rule)
      rule.handler.recurrence(rule, index)
    end

    def matches_now?(rule, _dtstart, now, node_key: "", timezone: default_timezone)
      matching_times(rule, now, node_key:, timezone:).any?
    end

    def rules_from_configuration(configuration)
      configuration = configuration.with_indifferent_access
      rules = CollectionParameters.rows(configuration, :rules)
      return rules if rules.present?

      Array.wrap(configuration.dig(:rule, :interval)).map { |rule| normalize_n8n_rule(rule) }
    end

    def valid_rule?(rule)
      rule = wrap(rule)
      return false if VALID_INTERVALS.exclude?(rule.interval)
      rule.handler.valid?(rule)
    end

    def seconds_rule?(rule)
      wrap(rule).interval == "seconds"
    end

    def seconds_interval(rule)
      (wrap(rule)[:seconds_between_triggers] || 30).to_i.clamp(1, 59)
    end

    def start_seconds_chain!(published_trigger, rule_index, rule)
      workflow = published_trigger.workflow
      node_id = published_trigger.trigger_node_id
      token = SecureRandom.uuid
      data = workflow.node_static_data(node_id)
      seconds_tokens = data.fetch("seconds_tokens") { {} }
      seconds_tokens[rule_index.to_s] = token
      workflow.update_node_static_data!(node_id, data.merge("seconds_tokens" => seconds_tokens))

      Jobs.enqueue_at(
        next_seconds_occurrence(Time.current.utc, seconds_interval(rule)),
        Jobs::DiscourseWorkflows::ExecuteSecondsSchedule,
        workflow_id: workflow.id,
        workflow_version_id: published_trigger.workflow_version_id,
        trigger_node_id: node_id,
        rule_index: rule_index,
        token: token,
      )
    end

    def seconds_token_valid?(workflow, node_id, rule_index, token)
      data = workflow.node_static_data(node_id)
      current_token = data.dig("seconds_tokens", rule_index.to_s)
      current_token.present? && current_token == token
    end

    def seconds_needs_watchdog?(workflow, node_id, rule_index, rule, now)
      data = workflow.node_static_data(node_id)
      last_triggered = data.dig("seconds_last_triggered", rule_index.to_s)
      return true if last_triggered.blank?

      interval = seconds_interval(rule)
      elapsed = now - Time.zone.parse(last_triggered)
      elapsed > interval * 3
    end

    def mark_seconds_triggered!(workflow, node_id, rule_index, now)
      data = workflow.node_static_data(node_id)
      seconds_last = data.fetch("seconds_last_triggered") { {} }
      seconds_last[rule_index.to_s] = now.iso8601
      workflow.update_node_static_data!(
        node_id,
        data.merge("seconds_last_triggered" => seconds_last),
      )
    end

    def fire_matching_trigger!(published_trigger, now)
      workflow = published_trigger.workflow
      node_id = published_trigger.trigger_node_id
      timezone = timezone_for(published_trigger)
      node_key = "#{workflow.id}:#{node_id}"
      configuration = NodeData.parameters(published_trigger.trigger_node).with_indifferent_access
      rules = rules_from_configuration(configuration)

      rules.each_with_index do |rule, rule_index|
        next if seconds_rule?(rule)

        matching_times(rule, now, node_key:, timezone:).each do |scheduled_at|
          workflow.with_lock do
            unless claim_occurrence!(workflow, node_id, rule_index, rule, scheduled_at, timezone)
              next
            end

            DiscourseWorkflows::TriggerDispatcher.enqueue(
              published_trigger,
              trigger_data: Nodes::Schedule::V1.new.output(time: scheduled_at, timezone:),
              run_at: scheduled_at,
            )
          end
        end
      end
    end

    def restart_stalled_chains!(published_trigger, now)
      workflow = published_trigger.workflow
      node_id = published_trigger.trigger_node_id
      configuration = NodeData.parameters(published_trigger.trigger_node).with_indifferent_access
      rules = rules_from_configuration(configuration)

      rules.each_with_index do |rule, rule_index|
        next unless seconds_rule?(rule)
        next unless seconds_needs_watchdog?(workflow, node_id, rule_index, rule, now)

        start_seconds_chain!(published_trigger, rule_index, rule)
      end
    end

    def matching_times(rule, now, node_key:, timezone:)
      cron_expression = to_cron_expression(rule, node_key)
      return [] if cron_expression.blank?

      window_start = now.utc.beginning_of_minute
      (0..59).filter_map do |offset|
        scheduled_at = window_start + offset.seconds
        scheduled_at if CronParser.matches?(cron_expression, scheduled_at.in_time_zone(timezone))
      end
    end

    def claim_occurrence!(workflow, node_id, rule_index, rule, scheduled_at, timezone)
      data = workflow.node_static_data(node_id).deep_dup
      occurrence_key = "#{rule_index}:#{scheduled_at.utc.iso8601}"
      triggered_occurrences = Array.wrap(data[TRIGGERED_OCCURRENCES_KEY])
      return false if triggered_occurrences.include?(occurrence_key)

      recurrence_rule = recurrence(rule, rule_index)
      if recurrence_rule[:activated]
        recurrence_rules = Array.wrap(data[RECURRENCE_RULES_KEY])
        recurrence_value = recurrence_value(recurrence_rule, scheduled_at, timezone)
        unless recurrence_due?(recurrence_rule, recurrence_rules[rule_index], recurrence_value)
          return false
        end

        recurrence_rules[rule_index] = recurrence_value
        data[RECURRENCE_RULES_KEY] = recurrence_rules
      end

      triggered_occurrences = triggered_occurrences.last(MAX_TRIGGERED_OCCURRENCES - 1)
      data[TRIGGERED_OCCURRENCES_KEY] = triggered_occurrences + [occurrence_key]
      data["last_triggered_at"] = scheduled_at.utc.iso8601
      workflow.update_node_static_data!(node_id, data)
      true
    end

    def recurrence_due?(recurrence_rule, last_value, current_value)
      return true if last_value.nil?

      last_value = last_value.to_i
      interval_size = recurrence_rule[:interval_size]

      case recurrence_rule[:type_interval]
      when "hours"
        (current_value - last_value + 24) % 24 >= interval_size
      when "days"
        (current_value - last_value + 365) % 365 >= interval_size
      when "weeks"
        (current_value - last_value + 52) % 52 >= interval_size || current_value == last_value
      when "months"
        (current_value - last_value + 12) % 12 >= interval_size
      else
        false
      end
    end

    def recurrence_value(recurrence_rule, scheduled_at, timezone)
      local_time = scheduled_at.in_time_zone(timezone)

      case recurrence_rule[:type_interval]
      when "hours"
        local_time.hour
      when "days"
        local_time.yday
      when "weeks"
        local_time.to_date.strftime("%U").to_i + 1
      when "months"
        local_time.month - 1
      end
    end

    def inactive_recurrence
      { activated: false }
    end

    def recurrence_for(interval_size:, index:, type_interval:)
      return inactive_recurrence if interval_size == 1

      { activated: true, index:, interval_size:, type_interval: }
    end

    def stable_int(seed, label, min, max)
      hash = Digest::SHA256.digest("#{seed}:#{label}")
      min + (hash.unpack1("N") % (max - min))
    end

    def next_seconds_occurrence(now, interval)
      now = now.utc.change(usec: 0)
      matching_seconds = (0..59).select { |second| (second % interval).zero? }
      next_second = matching_seconds.find { |second| second > now.sec }

      return now.change(sec: next_second) if next_second

      (now + 1.minute).change(sec: matching_seconds.first)
    end

    def timezone_for(published_trigger)
      timezone =
        published_trigger.workflow_version&.settings&.dig("timezone").presence ||
          published_trigger.workflow&.settings&.dig("timezone").presence || default_timezone

      valid_timezone?(timezone) ? timezone : default_timezone
    end

    def normalize_n8n_rule(rule)
      rule = rule.with_indifferent_access
      return rule if rule[:field].blank?

      case rule[:field]
      when "seconds"
        { "interval" => "seconds", "seconds_between_triggers" => rule[:secondsInterval] }.compact
      when "minutes"
        { "interval" => "minutes", "minutes_between_triggers" => rule[:minutesInterval] }.compact
      when "hours"
        {
          "interval" => "hours",
          "hours_between_triggers" => rule[:hoursInterval],
          "trigger_at_minute" => rule[:triggerAtMinute],
        }.compact
      when "days"
        {
          "interval" => "days",
          "days_between_triggers" => rule[:daysInterval],
          "trigger_at_hour" => rule[:triggerAtHour],
          "trigger_at_minute" => rule[:triggerAtMinute],
        }.compact
      when "weeks"
        {
          "interval" => "weeks",
          "weeks_between_triggers" => rule[:weeksInterval],
          "trigger_on_weekdays" => rule[:triggerAtDay],
          "trigger_at_hour" => rule[:triggerAtHour],
          "trigger_at_minute" => rule[:triggerAtMinute],
        }.compact
      when "months"
        {
          "interval" => "months",
          "months_between_triggers" => rule[:monthsInterval],
          "trigger_at_day_of_month" => rule[:triggerAtDayOfMonth],
          "trigger_at_hour" => rule[:triggerAtHour],
          "trigger_at_minute" => rule[:triggerAtMinute],
        }.compact
      when "cronExpression"
        { "interval" => "cronExpression", "cron" => rule[:expression] }.compact
      else
        rule
      end
    end

    def default_timezone
      timezone = Time.zone&.tzinfo&.name.presence
      timezone == "Etc/UTC" ? DEFAULT_TIMEZONE : (timezone || DEFAULT_TIMEZONE)
    end

    def valid_timezone?(timezone)
      return false if timezone.blank?

      TZInfo::Timezone.get(timezone)
      true
    rescue TZInfo::InvalidTimezoneIdentifier
      false
    end
  end
end
