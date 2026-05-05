# frozen_string_literal: true
class AddIndexToDiscourseWorkflowsExecutions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :discourse_workflows_executions,
                 %i[status waiting_until],
                 algorithm: :concurrently,
                 if_exists: true
    add_index :discourse_workflows_executions, %i[status waiting_until], algorithm: :concurrently
  end

  def down
    remove_index :discourse_workflows_executions,
                 %i[status waiting_until],
                 algorithm: :concurrently,
                 if_exists: true
  end
end
