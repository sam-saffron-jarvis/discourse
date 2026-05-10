# frozen_string_literal: true

class AddCreatedByIdToDiscourseWorkflowVariables < ActiveRecord::Migration[8.0]
  def change
    add_column :discourse_workflows_variables, :created_by_id, :integer, null: false
    add_index :discourse_workflows_variables, :created_by_id
  end
end
