class CreateQuestionnaireResponses < ActiveRecord::Migration[7.0]
  def change
    create_table :questionnaire_responses, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields (match ExtractionDefinitions::QuestionnaireResponse::FIELDS).
      # basedOn / partOf are 0..* references matched by jsonb containment (see
      # SearchDefinitions), so they have no extracted column here.
      t.string :questionnaire_canonical
      t.string :status
      t.string :subject_reference
      t.string :encounter_reference
      t.string :author_reference
      t.string :source_reference
      t.datetime :authored

      t.timestamps
    end

    add_index :questionnaire_responses, :questionnaire_canonical
    add_index :questionnaire_responses, :status
    add_index :questionnaire_responses, :subject_reference
    add_index :questionnaire_responses, :encounter_reference
    add_index :questionnaire_responses, :author_reference
    add_index :questionnaire_responses, :source_reference
    add_index :questionnaire_responses, :authored
    add_index :questionnaire_responses, :last_updated
    add_index :questionnaire_responses, :deleted
    add_index :questionnaire_responses, :content, using: :gin
  end
end
