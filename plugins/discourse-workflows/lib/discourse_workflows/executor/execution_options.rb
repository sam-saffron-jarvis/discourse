# frozen_string_literal: true

module DiscourseWorkflows
  class Executor
    ExecutionOptions =
      Data.define(:user, :execution_mode, :error_depth, :draft_execution, :workflow_version) do
        def initialize(
          user: nil,
          execution_mode: :normal,
          error_depth: 0,
          draft_execution: false,
          workflow_version: nil
        )
          super
        end
      end
  end
end
