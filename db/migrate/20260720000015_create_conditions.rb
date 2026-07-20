class CreateConditions < ActiveRecord::Migration[7.0]
  def change
    create_table :conditions, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :clinical_status
      t.string :verification_status
      t.string :category_code
      t.string :severity_code
      t.string :code_value
      t.string :code_text
      t.string :subject_reference
      t.string :encounter_reference
      t.datetime :onset_time
      t.datetime :recorded_time

      t.timestamps
    end

    add_index :conditions, :clinical_status
    add_index :conditions, :verification_status
    add_index :conditions, :category_code
    add_index :conditions, :code_value
    add_index :conditions, :subject_reference
    add_index :conditions, :encounter_reference
    add_index :conditions, :onset_time
    add_index :conditions, :recorded_time
    add_index :conditions, :last_updated
    add_index :conditions, :deleted
    add_index :conditions, :content, using: :gin
  end
end
