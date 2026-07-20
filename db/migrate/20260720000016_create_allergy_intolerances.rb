class CreateAllergyIntolerances < ActiveRecord::Migration[7.0]
  def change
    create_table :allergy_intolerances, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :clinical_status
      t.string :verification_status
      t.string :type_code
      t.string :category_code
      t.string :criticality
      t.string :code_value
      t.string :code_text
      t.string :patient_reference
      t.datetime :recorded_time

      t.timestamps
    end

    add_index :allergy_intolerances, :clinical_status
    add_index :allergy_intolerances, :category_code
    add_index :allergy_intolerances, :criticality
    add_index :allergy_intolerances, :code_value
    add_index :allergy_intolerances, :patient_reference
    add_index :allergy_intolerances, :recorded_time
    add_index :allergy_intolerances, :last_updated
    add_index :allergy_intolerances, :deleted
    add_index :allergy_intolerances, :content, using: :gin
  end
end
