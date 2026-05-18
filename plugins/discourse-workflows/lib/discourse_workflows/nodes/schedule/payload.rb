# frozen_string_literal: true

module DiscourseWorkflows
  module Nodes
    module Schedule
      module Payload
        module_function

        def build(time: Time.current, timezone: DiscourseWorkflows::WorkflowTimezone.default)
          local_time = time.in_time_zone(timezone)
          hour = local_time.hour % 12
          hour = 12 if hour.zero?
          readable_time = "#{hour}:#{local_time.strftime("%M:%S %P")}"

          {
            "timestamp" => local_time.iso8601(3),
            "Readable date" =>
              "#{local_time.strftime("%B")} #{local_time.day.ordinalize} #{local_time.year}, #{readable_time}",
            "Readable time" => readable_time,
            "Day of week" => local_time.strftime("%A"),
            "Year" => local_time.strftime("%Y"),
            "Month" => local_time.strftime("%B"),
            "Day of month" => local_time.strftime("%d"),
            "Hour" => local_time.strftime("%H"),
            "Minute" => local_time.strftime("%M"),
            "Second" => local_time.strftime("%S"),
            "Timezone" => "#{timezone} (UTC#{local_time.formatted_offset})",
          }
        end
      end
    end
  end
end
