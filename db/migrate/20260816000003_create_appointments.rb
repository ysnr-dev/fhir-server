class CreateAppointments < ActiveRecord::Migration[8.0]
  def change
    create_table :appointments, id: :string do |t|
      t.integer :version_id, null: false, default: 1
      t.jsonb :content, null: false
      t.boolean :deleted, null: false, default: false
      t.datetime :last_updated, null: false

      # Search-optimized extracted fields (match ExtractionDefinitions::Appointment::FIELDS).
      # Appointment has no single-valued Patient element -- the patient is one of the
      # 1..* participants -- but patient-compartment membership is derived from an
      # indexed single-valued column, so the Patient actor is flattened into
      # patient_reference (see ExtractionDefinitions::Appointment).
      # slot / basedOn / reasonReference and the other participants are 0..* and
      # matched by jsonb containment, so they have no column here.
      t.string :status
      t.string :appointment_type
      t.string :patient_reference
      t.datetime :start_time

      t.timestamps
    end

    add_index :appointments, :status
    add_index :appointments, :appointment_type
    add_index :appointments, :patient_reference
    add_index :appointments, :start_time
    add_index :appointments, :last_updated
    add_index :appointments, :deleted
    add_index :appointments, :content, using: :gin
  end
end
