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
          attribute :action_type, :string
          attribute :channel_id, :integer

          before_validation do
            payload = ::DiscourseWorkflows::WaitingExecution.action_token_payload(action_token)
            next if payload.blank?

            self.execution_id = payload["execution_id"]
            self.action_type = payload["action"]
          end

          validates :execution_id, presence: true
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
          ::DiscourseWorkflows::WaitingExecution.find_by_action_token(
            params.action_token,
            expected_node_type: "action:chat_approval",
          )
        end

        def fetch_claimed_execution(execution:)
          ::DiscourseWorkflows::Execution.claim_for_resume(
            execution,
            resume_token: execution.resume_token,
          )
        end

        def resume_execution(claimed_execution:, params:)
          response_items = [
            {
              "json" => {
                "approved" => params.action_type == "approve",
                "channel_id" => params.channel_id,
              },
            },
          ]
          ::DiscourseWorkflows::WaitingExecution.resume_claimed(claimed_execution, response_items)
        end
      end
    end
  end
end
