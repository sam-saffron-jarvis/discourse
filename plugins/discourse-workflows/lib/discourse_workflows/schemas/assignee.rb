# frozen_string_literal: true

module DiscourseWorkflows
  module Schemas
    class Assignee
      BASE_FIELDS = {
        type: :string,
        user: {
          type: :object,
          fields: User.fields,
        },
        group: {
          type: :object,
          fields: Group.fields,
        },
      }.freeze

      def self.fields
        BASE_FIELDS
      end

      def self.resolve(assignee)
        case assignee
        when ::User
          { type: "user", user: User.resolve(assignee), group: {} }
        when ::Group
          { type: "group", user: {}, group: Group.resolve(assignee) }
        else
          { type: nil, user: {}, group: {} }
        end
      end
    end
  end
end
