# frozen_string_literal: true
class DropWorkflowForeignKeys < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :discourse_workflows_execution_data,
                       :discourse_workflows_executions,
                       if_exists: true
    remove_foreign_key :discourse_workflows_workflow_dependencies,
                       :discourse_workflows_workflows,
                       if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
