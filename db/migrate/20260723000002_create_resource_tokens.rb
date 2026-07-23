class CreateResourceTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :resource_tokens do |t|
      t.string :resource_type, null: false
      t.string :resource_id,   null: false
      # Canonical search-parameter name this coding is indexed under (e.g. "code",
      # "category", "status"). One resource contributes many rows across params.
      t.string :param_name,    null: false
      t.string :system                        # coding.system (nullable = no system)
      t.string :code,          null: false     # coding.code / primitive / identifier value
      t.timestamps
      t.index %i[resource_type resource_id]
      t.index %i[resource_type param_name code]
      t.index %i[resource_type param_name system code]
    end
  end
end
