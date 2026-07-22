class AddRevocationToAccessTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :access_tokens, :revoked_at, :datetime
    # 期限切れトークンの定期purge(rake fhir:purge_expired)用
    add_index :access_tokens, :expires_at
  end
end
