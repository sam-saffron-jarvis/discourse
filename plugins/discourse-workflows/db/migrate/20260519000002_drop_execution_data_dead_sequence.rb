# frozen_string_literal: true

class DropExecutionDataDeadSequence < ActiveRecord::Migration[8.0]
  def up
    change_column_default :discourse_workflows_execution_data, :execution_id, nil
    execute "DROP SEQUENCE IF EXISTS discourse_workflows_execution_data_execution_id_seq"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
