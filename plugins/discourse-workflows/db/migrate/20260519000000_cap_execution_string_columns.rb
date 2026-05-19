# frozen_string_literal: true

class CapExecutionStringColumns < ActiveRecord::Migration[8.0]
  def change
    change_column :discourse_workflows_executions, :waiting_node_id, :string, limit: 100
    change_column :discourse_workflows_executions, :trigger_node_id, :string, limit: 100
    change_column :discourse_workflows_executions, :resume_token, :string, limit: 64
    change_column :discourse_workflows_executions, :timeout_action, :string, limit: 32
  end
end
