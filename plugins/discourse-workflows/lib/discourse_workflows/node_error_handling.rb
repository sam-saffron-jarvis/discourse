# frozen_string_literal: true

module DiscourseWorkflows
  module NodeErrorHandling
    private

    def raise_node_error!(message, description:, item_index: nil, line_number: nil)
      suffix = +""
      suffix << " [line #{line_number}" if line_number
      suffix << (line_number ? ", for item #{item_index}" : " [item #{item_index}") if item_index
      suffix.presence&.<<("]")

      raise DiscourseWorkflows::NodeError, "#{message}#{suffix}: #{description}"
    end
  end
end
