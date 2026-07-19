# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2026_07_19_121324) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "medication_request_identifiers", force: :cascade do |t|
    t.string "medication_request_id", null: false
    t.string "system"
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["medication_request_id"], name: "index_medication_request_identifiers_on_medication_request_id"
    t.index ["system", "value"], name: "index_medication_request_identifiers_on_system_and_value"
    t.index ["value"], name: "index_medication_request_identifiers_on_value"
  end

  create_table "medication_request_versions", force: :cascade do |t|
    t.string "medication_request_id", null: false
    t.integer "version_id", null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["medication_request_id", "version_id"], name: "index_med_request_versions_on_request_id_and_version_id", unique: true
  end

  create_table "medication_requests", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.string "status"
    t.string "intent"
    t.string "subject_reference"
    t.datetime "authored_on"
    t.string "medication_code"
    t.string "medication_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["authored_on"], name: "index_medication_requests_on_authored_on"
    t.index ["content"], name: "index_medication_requests_on_content", using: :gin
    t.index ["deleted"], name: "index_medication_requests_on_deleted"
    t.index ["intent"], name: "index_medication_requests_on_intent"
    t.index ["last_updated"], name: "index_medication_requests_on_last_updated"
    t.index ["medication_code"], name: "index_medication_requests_on_medication_code"
    t.index ["medication_text"], name: "index_medication_requests_on_medication_text"
    t.index ["status"], name: "index_medication_requests_on_status"
    t.index ["subject_reference"], name: "index_medication_requests_on_subject_reference"
  end

  create_table "organization_identifiers", force: :cascade do |t|
    t.string "organization_id", null: false
    t.string "system"
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_organization_identifiers_on_organization_id"
    t.index ["system", "value"], name: "index_organization_identifiers_on_system_and_value"
    t.index ["value"], name: "index_organization_identifiers_on_value"
  end

  create_table "organization_versions", force: :cascade do |t|
    t.string "organization_id", null: false
    t.integer "version_id", null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "version_id"], name: "index_organization_versions_on_request_and_version", unique: true
  end

  create_table "organizations", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.boolean "active"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_organizations_on_active"
    t.index ["content"], name: "index_organizations_on_content", using: :gin
    t.index ["deleted"], name: "index_organizations_on_deleted"
    t.index ["last_updated"], name: "index_organizations_on_last_updated"
    t.index ["name"], name: "index_organizations_on_name"
  end

  create_table "patient_identifiers", force: :cascade do |t|
    t.string "patient_id", null: false
    t.string "system"
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["patient_id"], name: "index_patient_identifiers_on_patient_id"
    t.index ["system", "value"], name: "index_patient_identifiers_on_system_and_value"
    t.index ["value"], name: "index_patient_identifiers_on_value"
  end

  create_table "patient_versions", force: :cascade do |t|
    t.string "patient_id", null: false
    t.integer "version_id", null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["patient_id", "version_id"], name: "index_patient_versions_on_patient_id_and_version_id", unique: true
  end

  create_table "patients", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.boolean "active"
    t.string "family"
    t.string "given"
    t.string "name_text"
    t.string "gender"
    t.date "birth_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["birth_date"], name: "index_patients_on_birth_date"
    t.index ["content"], name: "index_patients_on_content", using: :gin
    t.index ["deleted"], name: "index_patients_on_deleted"
    t.index ["family"], name: "index_patients_on_family"
    t.index ["gender"], name: "index_patients_on_gender"
    t.index ["last_updated"], name: "index_patients_on_last_updated"
    t.index ["name_text"], name: "index_patients_on_name_text"
  end

  create_table "practitioner_identifiers", force: :cascade do |t|
    t.string "practitioner_id", null: false
    t.string "system"
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["practitioner_id"], name: "index_practitioner_identifiers_on_practitioner_id"
    t.index ["system", "value"], name: "index_practitioner_identifiers_on_system_and_value"
    t.index ["value"], name: "index_practitioner_identifiers_on_value"
  end

  create_table "practitioner_versions", force: :cascade do |t|
    t.string "practitioner_id", null: false
    t.integer "version_id", null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["practitioner_id", "version_id"], name: "index_practitioner_versions_on_request_and_version", unique: true
  end

  create_table "practitioners", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.boolean "active"
    t.string "family"
    t.string "given"
    t.string "name_text"
    t.string "gender"
    t.date "birth_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["birth_date"], name: "index_practitioners_on_birth_date"
    t.index ["content"], name: "index_practitioners_on_content", using: :gin
    t.index ["deleted"], name: "index_practitioners_on_deleted"
    t.index ["family"], name: "index_practitioners_on_family"
    t.index ["gender"], name: "index_practitioners_on_gender"
    t.index ["last_updated"], name: "index_practitioners_on_last_updated"
    t.index ["name_text"], name: "index_practitioners_on_name_text"
  end

  create_table "service_request_identifiers", force: :cascade do |t|
    t.string "service_request_id", null: false
    t.string "system"
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["service_request_id"], name: "index_service_request_identifiers_on_service_request_id"
    t.index ["system", "value"], name: "index_service_request_identifiers_on_system_and_value"
    t.index ["value"], name: "index_service_request_identifiers_on_value"
  end

  create_table "service_request_versions", force: :cascade do |t|
    t.string "service_request_id", null: false
    t.integer "version_id", null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["service_request_id", "version_id"], name: "index_service_request_versions_on_request_and_version", unique: true
  end

  create_table "service_requests", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.string "status"
    t.string "intent"
    t.string "subject_reference"
    t.datetime "authored_on"
    t.string "code"
    t.string "code_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["authored_on"], name: "index_service_requests_on_authored_on"
    t.index ["code"], name: "index_service_requests_on_code"
    t.index ["code_text"], name: "index_service_requests_on_code_text"
    t.index ["content"], name: "index_service_requests_on_content", using: :gin
    t.index ["deleted"], name: "index_service_requests_on_deleted"
    t.index ["intent"], name: "index_service_requests_on_intent"
    t.index ["last_updated"], name: "index_service_requests_on_last_updated"
    t.index ["status"], name: "index_service_requests_on_status"
    t.index ["subject_reference"], name: "index_service_requests_on_subject_reference"
  end

  add_foreign_key "medication_request_identifiers", "medication_requests"
  add_foreign_key "organization_identifiers", "organizations"
  add_foreign_key "patient_identifiers", "patients"
  add_foreign_key "practitioner_identifiers", "practitioners"
  add_foreign_key "service_request_identifiers", "service_requests"
end
