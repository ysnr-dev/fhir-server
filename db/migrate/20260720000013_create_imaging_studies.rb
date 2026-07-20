class CreateImagingStudies < ActiveRecord::Migration[7.0]
  def change
    create_table :imaging_studies, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :modality_code
      t.string :subject_reference
      t.string :encounter_reference
      t.datetime :started

      t.timestamps
    end

    add_index :imaging_studies, :status
    add_index :imaging_studies, :modality_code
    add_index :imaging_studies, :subject_reference
    add_index :imaging_studies, :encounter_reference
    add_index :imaging_studies, :started
    add_index :imaging_studies, :last_updated
    add_index :imaging_studies, :deleted
    add_index :imaging_studies, :content, using: :gin
  end
end
