# frozen_string_literal: true

module DiscourseWorkflows
  module ConnectionIndex
    def self.from(connection, legacy_key, index_key)
      return connection[index_key].to_i if connection.key?(index_key)

      legacy(connection[legacy_key])
    end

    def self.legacy(value)
      value = value.to_s
      return 0 if value.blank? || value == "main" || value == "true" || value == "done"

      match = value.match(/\Ainput_(\d+)\z/)
      return match[1].to_i - 1 if match

      return 1 if %w[false loop].include?(value)

      value.to_i
    end
  end
end
