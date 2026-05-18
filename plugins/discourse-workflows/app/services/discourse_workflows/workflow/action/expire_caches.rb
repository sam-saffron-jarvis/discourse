# frozen_string_literal: true

module DiscourseWorkflows
  class Workflow::Action::ExpireCaches < Service::ActionBase
    def call
      WorkflowDependency.clear_cache!
    end
  end
end
