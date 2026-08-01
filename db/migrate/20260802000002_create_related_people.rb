class CreateRelatedPeople < ActiveRecord::Migration[8.0]
  def change
    create_table :related_people, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields (match ExtractionDefinitions::RelatedPerson::FIELDS).
      # RelatedPerson.patient is 1..1, so every row is in exactly one patient compartment.
      t.boolean :active
      t.string :patient_reference
      t.string :relationship_code
      t.string :name_text
      t.string :gender
      t.date :birth_date

      t.timestamps
    end

    add_index :related_people, :active
    add_index :related_people, :patient_reference
    add_index :related_people, :relationship_code
    add_index :related_people, :name_text
    add_index :related_people, :gender
    add_index :related_people, :birth_date
    add_index :related_people, :last_updated
    add_index :related_people, :deleted
    add_index :related_people, :content, using: :gin
  end
end
