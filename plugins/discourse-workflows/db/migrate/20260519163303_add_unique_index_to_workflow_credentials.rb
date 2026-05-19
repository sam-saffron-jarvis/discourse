# frozen_string_literal: true

class AddUniqueIndexToWorkflowCredentials < ActiveRecord::Migration[8.0]
  def change
    add_index :discourse_workflows_credentials, %i[name credential_type], unique: true
  end
end
