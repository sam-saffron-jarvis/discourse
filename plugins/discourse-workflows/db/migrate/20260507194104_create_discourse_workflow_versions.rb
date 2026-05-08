# frozen_string_literal: true

class CreateDiscourseWorkflowVersions < ActiveRecord::Migration[8.0]
  def up
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

    add_column :discourse_workflows_workflows, :draft_version_id, :bigint
    add_column :discourse_workflows_workflows, :published_version_id, :bigint
    add_index :discourse_workflows_workflows, :draft_version_id
    add_index :discourse_workflows_workflows, :published_version_id

    add_column :discourse_workflows_workflow_dependencies, :workflow_version_id, :bigint
    add_index :discourse_workflows_workflow_dependencies,
              :workflow_version_id,
              name: "idx_dwf_deps_workflow_version_id"

    execute <<~SQL
      INSERT INTO discourse_workflows_workflow_versions (
        workflow_id,
        version_number,
        name,
        nodes,
        connections,
        settings,
        static_data,
        created_by_id,
        updated_by_id,
        created_at,
        updated_at
      )
      SELECT
        id,
        1,
        name,
        COALESCE(nodes, '[]'::jsonb),
        COALESCE(connections, '[]'::jsonb),
        COALESCE(settings, '{}'::jsonb),
        COALESCE(static_data, '{}'::jsonb),
        created_by_id,
        updated_by_id,
        created_at,
        updated_at
      FROM discourse_workflows_workflows
    SQL

    execute <<~SQL
      UPDATE discourse_workflows_workflows workflows
      SET
        draft_version_id = versions.id,
        published_version_id = CASE WHEN workflows.enabled THEN versions.id ELSE NULL END
      FROM discourse_workflows_workflow_versions versions
      WHERE versions.workflow_id = workflows.id
        AND versions.version_number = 1
    SQL

    execute <<~SQL
      UPDATE discourse_workflows_workflow_dependencies dependencies
      SET
        workflow_version_id = workflows.draft_version_id
      FROM discourse_workflows_workflows workflows
      WHERE workflows.id = dependencies.workflow_id
    SQL
  end

  def down
    remove_index :discourse_workflows_workflow_dependencies,
                 name: "idx_dwf_deps_workflow_version_id"
    remove_column :discourse_workflows_workflow_dependencies, :workflow_version_id

    remove_index :discourse_workflows_workflows, :published_version_id
    remove_index :discourse_workflows_workflows, :draft_version_id
    remove_column :discourse_workflows_workflows, :published_version_id
    remove_column :discourse_workflows_workflows, :draft_version_id

    drop_table :discourse_workflows_workflow_versions
  end
end
