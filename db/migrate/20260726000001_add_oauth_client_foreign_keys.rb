# refresh_tokens / client_assertion_jtis / bulk_exports は oauth_client_id を
# 持ちながらFK制約が無く、クライアントを削除すると孤児行が残っていた。特に
# refresh_tokens の孤児は「所有クライアントが nil のまま有効」なトークンになり、
# OauthTokensController#refresh_token_grant が nil.public_client? で 500 を返す。
#
# モデル側の has_many ... dependent で観測されたバグは直るが、将来の削除経路
# (delete_all / SQL直打ち)で再発しないようDBにも制約を張る。
class AddOauthClientForeignKeys < ActiveRecord::Migration[8.0]
  def up
    # 既にデプロイ済みのDBにはこの修正より前に作られた孤児行が居る可能性がある。
    # FKを張る前に掃除しないとマイグレーション自体が失敗する。
    execute <<~SQL.squish
      DELETE FROM refresh_tokens
      WHERE oauth_client_id NOT IN (SELECT id FROM oauth_clients)
    SQL
    execute <<~SQL.squish
      DELETE FROM refresh_tokens
      WHERE authorization_code_id NOT IN (SELECT id FROM authorization_codes)
    SQL
    execute <<~SQL.squish
      DELETE FROM client_assertion_jtis
      WHERE oauth_client_id NOT IN (SELECT id FROM oauth_clients)
    SQL
    execute <<~SQL.squish
      UPDATE bulk_exports SET oauth_client_id = NULL
      WHERE oauth_client_id IS NOT NULL
        AND oauth_client_id NOT IN (SELECT id FROM oauth_clients)
    SQL

    # on_delete: :cascade は使わない。このアプリはカスケードをRuby側
    # (dependent:)に明示する方針で、bulk_export_files だけが例外。
    add_foreign_key :refresh_tokens, :oauth_clients
    add_foreign_key :refresh_tokens, :authorization_codes
    add_foreign_key :client_assertion_jtis, :oauth_clients
    add_foreign_key :bulk_exports, :oauth_clients
  end

  def down
    remove_foreign_key :bulk_exports, :oauth_clients
    remove_foreign_key :client_assertion_jtis, :oauth_clients
    remove_foreign_key :refresh_tokens, :authorization_codes
    remove_foreign_key :refresh_tokens, :oauth_clients
  end
end
