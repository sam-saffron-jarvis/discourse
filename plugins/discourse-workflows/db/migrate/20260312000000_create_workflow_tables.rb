# frozen_string_literal: true

class CreateWorkflowTables < ActiveRecord::Migration[8.0]
  def change
    create_table :discourse_workflows_workflows do |t|
      t.string :name, null: false
      t.jsonb :nodes, default: []
      t.jsonb :connections, default: []
      t.jsonb :static_data, default: {}
      t.jsonb :settings
      t.bigint :error_workflow_id
      t.bigint :draft_version_id
      t.bigint :published_version_id
      t.integer :created_by_id, null: false
      t.integer :updated_by_id
      t.timestamps null: false
    end

    add_index :discourse_workflows_workflows, :created_by_id
    add_index :discourse_workflows_workflows, :updated_by_id
    add_index :discourse_workflows_workflows, :error_workflow_id
    add_index :discourse_workflows_workflows, :draft_version_id
    add_index :discourse_workflows_workflows, :published_version_id
    add_index :discourse_workflows_workflows, :nodes, using: :gin, name: "idx_workflows_nodes_gin"

    create_table :discourse_workflows_workflow_versions do |t|
      t.bigint :workflow_id, null: false
      t.integer :version_number, null: false
      t.string :name, null: false, limit: 100
      t.jsonb :nodes, null: false, default: []
      t.jsonb :connections, null: false, default: []
      t.jsonb :settings, null: false, default: {}
      t.jsonb :static_data, null: false, default: {}
      t.integer :created_by_id, null: false
      t.integer :updated_by_id
      t.timestamps null: false
    end

    add_index :discourse_workflows_workflow_versions, :workflow_id
    add_index :discourse_workflows_workflow_versions,
              %i[workflow_id version_number],
              unique: true,
              name: "idx_dwf_versions_workflow_version_number"

    create_table :discourse_workflows_executions do |t|
      t.bigint :workflow_id, null: false
      t.integer :status, null: false, default: 0
      t.integer :execution_mode, default: 0, null: false
      t.jsonb :trigger_data, default: {}
      t.text :error
      t.string :waiting_node_id
      t.datetime :waiting_until
      t.string :resume_token
      t.string :timeout_action
      t.string :trigger_node_id
      t.integer :run_time_ms
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps null: false
    end

    add_index :discourse_workflows_executions, :workflow_id
    add_index :discourse_workflows_executions, :status
    add_index :discourse_workflows_executions, :waiting_node_id
    add_index :discourse_workflows_executions, :resume_token, where: "resume_token IS NOT NULL"
    add_index :discourse_workflows_executions,
              :waiting_until,
              where: "waiting_until IS NOT NULL AND status = 4",
              name: "idx_executions_waiting_until"
    add_index :discourse_workflows_executions, %i[status waiting_until]
    add_index :discourse_workflows_executions,
              %i[workflow_id created_at id],
              name: "idx_dwf_executions_workflow_created_at_id_desc",
              order: {
                created_at: :desc,
                id: :desc,
              }

    create_table :discourse_workflows_execution_data, id: false do |t|
      t.bigint :execution_id, null: false, primary_key: true
      t.text :data
      t.jsonb :workflow_data, default: {}, null: false
    end

    create_table :discourse_workflows_variables do |t|
      t.string :key, null: false, limit: 100
      t.string :value, null: false, default: "", limit: 1000
      t.text :description
      t.integer :created_by_id, null: false
      t.timestamps
    end

    add_index :discourse_workflows_variables, :key, unique: true
    add_index :discourse_workflows_variables, :created_by_id

    create_table :discourse_workflows_data_tables do |t|
      t.string :name, null: false, limit: 100
      t.timestamps null: false
    end

    add_index :discourse_workflows_data_tables, :name, unique: true

    create_table :discourse_workflows_credentials do |t|
      t.string :name, limit: 128, null: false
      t.string :credential_type, limit: 64, null: false
      t.text :data, null: false
      t.timestamps
    end

    add_index :discourse_workflows_credentials, :credential_type

    create_table :discourse_workflows_workflow_dependencies do |t|
      t.bigint :workflow_id, null: false
      t.string :dependency_type, null: false, limit: 50
      t.string :dependency_key, null: false, limit: 500
      t.string :node_id, limit: 100
      t.bigint :workflow_version_id
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :discourse_workflows_workflow_dependencies, :workflow_id
    add_index :discourse_workflows_workflow_dependencies,
              %i[dependency_type dependency_key],
              name: "idx_workflow_deps_type_key"
    add_index :discourse_workflows_workflow_dependencies,
              :workflow_version_id,
              name: "idx_dwf_deps_workflow_version_id"
  end
end
