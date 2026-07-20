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

ActiveRecord::Schema[7.0].define(version: 2026_07_20_000010) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "encounters", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.string "status"
    t.string "class_code"
    t.string "subject_reference"
    t.datetime "period_start"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "service_provider_reference"
    t.datetime "period_end"
    t.index ["class_code"], name: "index_encounters_on_class_code"
    t.index ["content"], name: "index_encounters_on_content", using: :gin
    t.index ["deleted"], name: "index_encounters_on_deleted"
    t.index ["last_updated"], name: "index_encounters_on_last_updated"
    t.index ["period_end"], name: "index_encounters_on_period_end"
    t.index ["period_start"], name: "index_encounters_on_period_start"
    t.index ["service_provider_reference"], name: "index_encounters_on_service_provider_reference"
    t.index ["status"], name: "index_encounters_on_status"
    t.index ["subject_reference"], name: "index_encounters_on_subject_reference"
  end

  create_table "locations", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.string "status"
    t.string "name"
    t.string "address_text"
    t.string "type_code"
    t.string "organization_reference"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "partof_reference"
    t.index ["address_text"], name: "index_locations_on_address_text"
    t.index ["content"], name: "index_locations_on_content", using: :gin
    t.index ["deleted"], name: "index_locations_on_deleted"
    t.index ["last_updated"], name: "index_locations_on_last_updated"
    t.index ["name"], name: "index_locations_on_name"
    t.index ["organization_reference"], name: "index_locations_on_organization_reference"
    t.index ["partof_reference"], name: "index_locations_on_partof_reference"
    t.index ["status"], name: "index_locations_on_status"
    t.index ["type_code"], name: "index_locations_on_type_code"
  end

  create_table "medication_administrations", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.string "status"
    t.string "subject_reference"
    t.string "medication_code"
    t.string "medication_text"
    t.string "context_reference"
    t.string "request_reference"
    t.datetime "effective_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content"], name: "index_medication_administrations_on_content", using: :gin
    t.index ["context_reference"], name: "index_medication_administrations_on_context_reference"
    t.index ["deleted"], name: "index_medication_administrations_on_deleted"
    t.index ["effective_time"], name: "index_medication_administrations_on_effective_time"
    t.index ["last_updated"], name: "index_medication_administrations_on_last_updated"
    t.index ["medication_code"], name: "index_medication_administrations_on_medication_code"
    t.index ["medication_text"], name: "index_medication_administrations_on_medication_text"
    t.index ["request_reference"], name: "index_medication_administrations_on_request_reference"
    t.index ["status"], name: "index_medication_administrations_on_status"
    t.index ["subject_reference"], name: "index_medication_administrations_on_subject_reference"
  end

  create_table "medication_dispenses", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.string "status"
    t.string "subject_reference"
    t.string "medication_code"
    t.string "medication_text"
    t.string "context_reference"
    t.datetime "when_handed_over"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content"], name: "index_medication_dispenses_on_content", using: :gin
    t.index ["context_reference"], name: "index_medication_dispenses_on_context_reference"
    t.index ["deleted"], name: "index_medication_dispenses_on_deleted"
    t.index ["last_updated"], name: "index_medication_dispenses_on_last_updated"
    t.index ["medication_code"], name: "index_medication_dispenses_on_medication_code"
    t.index ["medication_text"], name: "index_medication_dispenses_on_medication_text"
    t.index ["status"], name: "index_medication_dispenses_on_status"
    t.index ["subject_reference"], name: "index_medication_dispenses_on_subject_reference"
    t.index ["when_handed_over"], name: "index_medication_dispenses_on_when_handed_over"
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
    t.string "encounter_reference"
    t.string "requester_reference"
    t.index ["authored_on"], name: "index_medication_requests_on_authored_on"
    t.index ["content"], name: "index_medication_requests_on_content", using: :gin
    t.index ["deleted"], name: "index_medication_requests_on_deleted"
    t.index ["encounter_reference"], name: "index_medication_requests_on_encounter_reference"
    t.index ["intent"], name: "index_medication_requests_on_intent"
    t.index ["last_updated"], name: "index_medication_requests_on_last_updated"
    t.index ["medication_code"], name: "index_medication_requests_on_medication_code"
    t.index ["medication_text"], name: "index_medication_requests_on_medication_text"
    t.index ["requester_reference"], name: "index_medication_requests_on_requester_reference"
    t.index ["status"], name: "index_medication_requests_on_status"
    t.index ["subject_reference"], name: "index_medication_requests_on_subject_reference"
  end

  create_table "medication_statements", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.string "status"
    t.string "subject_reference"
    t.string "medication_code"
    t.string "medication_text"
    t.string "context_reference"
    t.datetime "effective_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content"], name: "index_medication_statements_on_content", using: :gin
    t.index ["context_reference"], name: "index_medication_statements_on_context_reference"
    t.index ["deleted"], name: "index_medication_statements_on_deleted"
    t.index ["effective_time"], name: "index_medication_statements_on_effective_time"
    t.index ["last_updated"], name: "index_medication_statements_on_last_updated"
    t.index ["medication_code"], name: "index_medication_statements_on_medication_code"
    t.index ["medication_text"], name: "index_medication_statements_on_medication_text"
    t.index ["status"], name: "index_medication_statements_on_status"
    t.index ["subject_reference"], name: "index_medication_statements_on_subject_reference"
  end

  create_table "medications", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.string "status"
    t.string "medication_code"
    t.string "medication_text"
    t.string "form_code"
    t.string "manufacturer_reference"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["content"], name: "index_medications_on_content", using: :gin
    t.index ["deleted"], name: "index_medications_on_deleted"
    t.index ["form_code"], name: "index_medications_on_form_code"
    t.index ["last_updated"], name: "index_medications_on_last_updated"
    t.index ["manufacturer_reference"], name: "index_medications_on_manufacturer_reference"
    t.index ["medication_code"], name: "index_medications_on_medication_code"
    t.index ["medication_text"], name: "index_medications_on_medication_text"
    t.index ["status"], name: "index_medications_on_status"
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
    t.string "partof_reference"
    t.index ["active"], name: "index_organizations_on_active"
    t.index ["content"], name: "index_organizations_on_content", using: :gin
    t.index ["deleted"], name: "index_organizations_on_deleted"
    t.index ["last_updated"], name: "index_organizations_on_last_updated"
    t.index ["name"], name: "index_organizations_on_name"
    t.index ["partof_reference"], name: "index_organizations_on_partof_reference"
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

  create_table "practitioner_roles", id: :string, force: :cascade do |t|
    t.integer "version_id", default: 1, null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.boolean "active"
    t.string "practitioner_reference"
    t.string "organization_reference"
    t.string "role_code"
    t.string "specialty_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_practitioner_roles_on_active"
    t.index ["content"], name: "index_practitioner_roles_on_content", using: :gin
    t.index ["deleted"], name: "index_practitioner_roles_on_deleted"
    t.index ["last_updated"], name: "index_practitioner_roles_on_last_updated"
    t.index ["organization_reference"], name: "index_practitioner_roles_on_organization_reference"
    t.index ["practitioner_reference"], name: "index_practitioner_roles_on_practitioner_reference"
    t.index ["role_code"], name: "index_practitioner_roles_on_role_code"
    t.index ["specialty_code"], name: "index_practitioner_roles_on_specialty_code"
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

  create_table "resource_identifiers", force: :cascade do |t|
    t.string "resource_type", null: false
    t.string "resource_id", null: false
    t.string "system"
    t.string "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_type", "resource_id"], name: "index_resource_identifiers_on_resource_type_and_resource_id"
    t.index ["system", "value"], name: "index_resource_identifiers_on_system_and_value"
    t.index ["value"], name: "index_resource_identifiers_on_value"
  end

  create_table "resource_versions", force: :cascade do |t|
    t.string "resource_type", null: false
    t.string "resource_id", null: false
    t.integer "version_id", null: false
    t.jsonb "content", null: false
    t.boolean "deleted", default: false, null: false
    t.datetime "last_updated", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resource_type", "resource_id", "version_id"], name: "index_resource_versions_on_type_id_version", unique: true
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
    t.string "encounter_reference"
    t.string "requester_reference"
    t.index ["authored_on"], name: "index_service_requests_on_authored_on"
    t.index ["code"], name: "index_service_requests_on_code"
    t.index ["code_text"], name: "index_service_requests_on_code_text"
    t.index ["content"], name: "index_service_requests_on_content", using: :gin
    t.index ["deleted"], name: "index_service_requests_on_deleted"
    t.index ["encounter_reference"], name: "index_service_requests_on_encounter_reference"
    t.index ["intent"], name: "index_service_requests_on_intent"
    t.index ["last_updated"], name: "index_service_requests_on_last_updated"
    t.index ["requester_reference"], name: "index_service_requests_on_requester_reference"
    t.index ["status"], name: "index_service_requests_on_status"
    t.index ["subject_reference"], name: "index_service_requests_on_subject_reference"
  end

end
