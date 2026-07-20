class PractitionerRole < ApplicationRecord
  include FhirResourceRecord

  # Derives the search-optimized columns from the FHIR `content` payload.
  # Called before every persist so the extracted columns never drift from content.
  def sync_search_fields!
    resource = content || {}

    self.active = resource["active"]
    self.practitioner_reference = resource.dig("practitioner", "reference")
    self.organization_reference = resource.dig("organization", "reference")
    self.role_code = first_coding_code(resource["code"])
    self.specialty_code = first_coding_code(resource["specialty"])
  end

  private

  # code and specialty are 0..* CodeableConcept; index the first coding's code.
  def first_coding_code(concepts)
    coding = Array(concepts).first&.dig("coding")
    Array(coding).first&.dig("code")
  end
end
