class CreateQuestionnaires < ActiveRecord::Migration[7.0]
  def change
    create_table :questionnaires, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields (match ExtractionDefinitions::Questionnaire::FIELDS).
      # Questionnaire has no Reference elements at all -- it is definitional data,
      # so there are no *_reference columns here and no patient compartment.
      t.string :url
      t.string :version
      t.string :name
      t.string :title
      t.string :status
      t.string :subject_type
      t.string :publisher
      t.string :code_value
      t.datetime :questionnaire_date

      t.timestamps
    end

    add_index :questionnaires, :url
    add_index :questionnaires, :version
    add_index :questionnaires, :name
    add_index :questionnaires, :title
    add_index :questionnaires, :status
    add_index :questionnaires, :subject_type
    add_index :questionnaires, :publisher
    add_index :questionnaires, :code_value
    add_index :questionnaires, :questionnaire_date
    add_index :questionnaires, :last_updated
    add_index :questionnaires, :deleted
    add_index :questionnaires, :content, using: :gin
  end
end
