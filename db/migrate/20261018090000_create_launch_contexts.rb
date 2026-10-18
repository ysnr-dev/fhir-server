class CreateLaunchContexts < ActiveRecord::Migration[7.0]
  def change
    # EHR launch の起動文脈。カルテ(fhir-client)が管理 API で発行し、アプリが
    # /oauth/authorize に `launch` として持ってくる。5 分・単回使用。
    create_table :launch_contexts do |t|
      t.string :token_digest, null: false
      t.string :oauth_client_id, null: false
      t.string :patient_id, null: false
      t.string :encounter_id
      t.string :practitioner_id, null: false
      t.boolean :need_patient_banner, null: false, default: false
      t.string :issued_by
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :launch_contexts, :token_digest, unique: true
    add_index :launch_contexts, :oauth_client_id
    add_index :launch_contexts, :expires_at
    add_foreign_key :launch_contexts, :oauth_clients

    # 医療者(Practitioner)として発行されるグラントは上流に User を持たない。
    change_column_null :authorization_codes, :user_id, true
    add_column :authorization_codes, :practitioner_id, :string
    add_column :authorization_codes, :encounter_id, :string
    add_reference :authorization_codes, :launch_context, foreign_key: { on_delete: :nullify }

    change_column_null :refresh_tokens, :user_id, true
    add_column :refresh_tokens, :practitioner_id, :string
    add_column :refresh_tokens, :encounter_id, :string

    add_column :access_tokens, :practitioner_id, :string
    add_column :access_tokens, :encounter_id, :string

    # 「どのアプリが(client)・誰として(agent)」を分けて残す。
    add_column :audit_events, :agent_who_reference, :string
  end
end
