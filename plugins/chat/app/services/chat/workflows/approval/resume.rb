# frozen_string_literal: true

module Chat
  module Workflows
    module Approval
      class Resume
        include Service::Base

        policy :workflows_enabled

        params do
          attribute :execution_id, :integer
          attribute :approved, :boolean
          attribute :action_token, :string
          attribute :resume_token, :string
          attribute :action_type, :string
          attribute :channel_id, :integer

          before_validation do
            self.resume_token, self.action_type = action_token.to_s.split(":", 2)
          end

          validates :execution_id, presence: true
          validates :resume_token, presence: true
          validates :action_type, inclusion: { in: %w[approve deny] }
        end

        model :execution
        model :claimed_execution
        step :resume_execution

        private

        def workflows_enabled
          SiteSetting.discourse_workflows_enabled
        end

        def fetch_execution(params:)
          ::DiscourseWorkflows::Execution.by_resume_token(params.resume_token).find_by(
            id: params.execution_id,
          )
        end

        def fetch_claimed_execution(execution:, params:)
          ::DiscourseWorkflows::Execution.claim_for_resume(
            execution,
            resume_token: params.resume_token,
          )
        end

        def resume_execution(claimed_execution:, params:)
          response_items = [
            { "json" => { "approved" => params.approved, "channel_id" => params.channel_id } },
          ]
          ::DiscourseWorkflows::Executor.resume(claimed_execution, response_items)
        end
      end
    end
  end
end
