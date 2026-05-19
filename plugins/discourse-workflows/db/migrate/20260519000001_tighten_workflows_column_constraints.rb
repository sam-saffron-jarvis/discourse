# frozen_string_literal: true

class TightenWorkflowsColumnConstraints < ActiveRecord::Migration[8.0]
  def up
    change_column :discourse_workflows_workflows, :name, :string, limit: 100

    change_column_default :discourse_workflows_workflows, :settings, {}

    change_column_null :discourse_workflows_workflows, :nodes, false
    change_column_null :discourse_workflows_workflows, :connections, false
    change_column_null :discourse_workflows_workflows, :settings, false
    change_column_null :discourse_workflows_workflows, :static_data, false
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
