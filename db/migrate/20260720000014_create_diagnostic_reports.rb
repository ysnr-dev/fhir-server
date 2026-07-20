class CreateDiagnosticReports < ActiveRecord::Migration[7.0]
  def change
    create_table :diagnostic_reports, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :category_code
      t.string :code_value
      t.string :code_text
      t.string :subject_reference
      t.string :encounter_reference
      t.datetime :effective_time

      t.timestamps
    end

    add_index :diagnostic_reports, :status
    add_index :diagnostic_reports, :category_code
    add_index :diagnostic_reports, :code_value
    add_index :diagnostic_reports, :code_text
    add_index :diagnostic_reports, :subject_reference
    add_index :diagnostic_reports, :encounter_reference
    add_index :diagnostic_reports, :effective_time
    add_index :diagnostic_reports, :last_updated
    add_index :diagnostic_reports, :deleted
    add_index :diagnostic_reports, :content, using: :gin
  end
end
