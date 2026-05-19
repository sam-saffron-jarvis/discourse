# frozen_string_literal: true

class DropRedundantExecutionIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEXES = %i[
    index_discourse_workflows_executions_on_workflow_id
    index_discourse_workflows_executions_on_status
    index_discourse_workflows_executions_on_waiting_node_id
  ]

  def change
    INDEXES.each do |name|
      remove_index :discourse_workflows_executions,
                   name: name,
                   algorithm: :concurrently,
                   if_exists: true
    end
  end
end
