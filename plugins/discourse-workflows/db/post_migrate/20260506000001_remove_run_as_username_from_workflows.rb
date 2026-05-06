# frozen_string_literal: true

class RemoveRunAsUsernameFromWorkflows < ActiveRecord::Migration[7.2]
  def up
    if column_exists?(:discourse_workflows_workflows, :run_as_username)
      remove_column :discourse_workflows_workflows, :run_as_username
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
