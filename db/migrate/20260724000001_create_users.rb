# Patient-facing accounts for the interactive SMART App Launch (standalone).
# Each account is bound 1:1 to a FHIR Patient; that binding is the launch
# context baked into every token issued through the authorization_code flow,
# which is why there is no patient picker.
class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name
      # FHIR Patient logical id (patients.id is a string, not a bigint).
      t.string :patient_id, null: false
      t.timestamps
    end

    add_index :users, :email, unique: true
    # Unique, not just an index: the 1:1 binding is enforced by the database so
    # a patient can never end up with two sets of credentials.
    add_index :users, :patient_id, unique: true
    add_foreign_key :users, :patients, column: :patient_id, primary_key: :id
  end
end
