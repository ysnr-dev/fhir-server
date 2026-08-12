class CreateTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :tasks, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields (match ExtractionDefinitions::Task::FIELDS).
      # Task.for is stored as for_reference: the element name is a Ruby keyword, and
      # the FHIR search param for it is "subject" (aliased "patient") anyway.
      # Task.basedOn / Task.partOf are 0..* and matched by jsonb containment, so
      # they have no column here.
      t.string :status
      t.string :intent
      t.string :priority
      t.string :business_status
      t.string :group_identifier
      t.string :performer_type
      t.string :code
      t.string :code_text
      t.string :for_reference
      t.string :encounter_reference
      t.string :requester_reference
      t.string :owner_reference
      t.string :focus_reference
      t.datetime :authored_on
      t.datetime :last_modified
      t.datetime :execution_period_start
      t.datetime :execution_period_end

      t.timestamps
    end

    add_index :tasks, :status
    add_index :tasks, :intent
    add_index :tasks, :priority
    add_index :tasks, :business_status
    add_index :tasks, :group_identifier
    add_index :tasks, :performer_type
    add_index :tasks, :code
    add_index :tasks, :code_text
    add_index :tasks, :for_reference
    add_index :tasks, :encounter_reference
    add_index :tasks, :requester_reference
    add_index :tasks, :owner_reference
    add_index :tasks, :focus_reference
    add_index :tasks, :authored_on
    add_index :tasks, :last_modified
    add_index :tasks, :execution_period_start
    add_index :tasks, :execution_period_end
    add_index :tasks, :last_updated
    add_index :tasks, :deleted
    add_index :tasks, :content, using: :gin
  end
end
