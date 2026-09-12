class CreateCarePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :care_plans, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :status
      t.string :intent
      t.string :subject_reference
      t.string :encounter_reference
      # CarePlan.period は計画が効いている期間。period_end が NULL なら継続中
      # (Encounter.period と同じ約束)。
      t.datetime :period_start
      t.datetime :period_end
      # 元にした定義。canonical(PlanDefinition の URL)と uri(FHIR の外にある定義)の
      # どちらで指すかは書き手次第なので、両方を別々に索引する。
      t.string :instantiates_canonical
      t.string :instantiates_uri

      t.timestamps
    end

    add_index :care_plans, :status
    add_index :care_plans, :intent
    add_index :care_plans, :subject_reference
    add_index :care_plans, :encounter_reference
    add_index :care_plans, :period_start
    add_index :care_plans, :instantiates_canonical
    add_index :care_plans, :instantiates_uri
    add_index :care_plans, :last_updated
    add_index :care_plans, :deleted
    # partOf / goal は 0..* の参照で、列ではなく content の jsonb 包含で引く。
    add_index :care_plans, :content, using: :gin
  end
end
