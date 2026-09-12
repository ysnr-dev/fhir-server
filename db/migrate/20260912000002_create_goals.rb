class CreateGoals < ActiveRecord::Migration[8.0]
  def change
    create_table :goals, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields
      t.string :lifecycle_status
      t.string :achievement_status
      t.string :subject_reference
      # Goal.start[x] は date か CodeableConcept(開始の契機)の choice。日付で
      # 書かれたときだけ索引し、契機コードは resource_tokens に載せない
      # (start-date は date 型の検索パラメータで、コードとは突き合わせられない)。
      t.date :start_date

      t.timestamps
    end

    add_index :goals, :lifecycle_status
    add_index :goals, :achievement_status
    add_index :goals, :subject_reference
    add_index :goals, :start_date
    add_index :goals, :last_updated
    add_index :goals, :deleted
    add_index :goals, :content, using: :gin
  end
end
