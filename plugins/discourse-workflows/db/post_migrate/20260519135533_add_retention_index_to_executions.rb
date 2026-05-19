# frozen_string_literal: true

class AddRetentionIndexToExecutions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :discourse_workflows_executions,
              :created_at,
              where: "status IN (2, 3, 5, 6)",
              name: "idx_dwf_executions_retention",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
