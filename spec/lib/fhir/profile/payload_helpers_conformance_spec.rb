require "rails_helper"

# Guards against the request-spec payload helpers (spec/support/*_payload_helper.rb)
# drifting out of JP Core conformance. Fhir::Profile.mode defaults to :warn,
# so a non-conformant helper doesn't fail any *other* spec -- this is the one
# place that would notice, which matters before anyone flips
# FHIR_PROFILE_VALIDATION to :enforce in production.
RSpec.describe "JP Core payload helper conformance", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_organization
    post "/Organization", params: valid_organization_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  let(:patient_id) { create_patient }
  let(:organization_id) { create_organization }

  # resourceType -> payload, built lazily so only the fixtures a given
  # example needs get their dependent Patient/Organization created.
  def payloads
    {
      "Patient" => valid_patient_payload,
      "Practitioner" => valid_practitioner_payload,
      "Organization" => valid_organization_payload,
      "PractitionerRole" => valid_practitioner_role_payload,
      "Location" => valid_location_payload,
      "Encounter" => valid_encounter_payload,
      "Condition" => valid_condition_payload(subject_id: patient_id),
      "AllergyIntolerance" => valid_allergy_intolerance_payload(patient_id: patient_id),
      "Procedure" => valid_procedure_payload(subject_id: patient_id),
      "Immunization" => valid_immunization_payload(patient_id: patient_id),
      "Observation" => valid_observation_payload(subject_id: patient_id),
      "Specimen" => valid_specimen_payload(subject_id: patient_id),
      "DiagnosticReport" => valid_diagnostic_report_payload(subject_id: patient_id),
      "ServiceRequest" => valid_service_request_payload(subject_id: patient_id),
      "Medication" => valid_medication_payload,
      "MedicationRequest" => valid_medication_request_payload(subject_id: patient_id),
      "MedicationDispense" => valid_medication_dispense_payload(subject_id: patient_id),
      "MedicationAdministration" => valid_medication_administration_payload(subject_id: patient_id),
      "MedicationStatement" => valid_medication_statement_payload(subject_id: patient_id),
      "Coverage" => valid_coverage_payload(beneficiary_id: patient_id, payor_id: organization_id)
    }
  end

  Fhir::ResourceRegistry::ENTRIES.each_key do |resource_type|
    entry = Fhir::ResourceRegistry.entry_for(resource_type)
    next unless Fhir::Profile.jp_core_profile?(entry[:profile])

    it "keeps valid_#{resource_type.underscore}_payload conformant with #{entry[:profile]}" do
      payload = payloads.fetch(resource_type)

      result = Fhir::Profile::Validator.call(payload, profile_url: entry[:profile])

      diagnostics = result.errors.map { |e| "#{e[:code]}: #{e[:diagnostics]}" }.join("\n")
      expect(result.valid?).to be(true), "#{resource_type} payload helper has JP Core issues:\n#{diagnostics}"
    end
  end
end
