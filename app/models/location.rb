class Location < ApplicationRecord
  include FhirResourceRecord

  # Derives the search-optimized columns from the FHIR `content` payload.
  # Called before every persist so the extracted columns never drift from content.
  def sync_search_fields!
    resource = content || {}

    self.status = resource["status"]
    self.name = resource["name"]
    self.address_text = flatten_address(resource["address"])
    self.type_code = first_coding_code(resource["type"])
    self.organization_reference = resource.dig("managingOrganization", "reference")
  end

  private

  def flatten_address(address)
    return nil if address.blank?

    [address["text"], *Array(address["line"]), address["city"], address["state"], address["postalCode"]]
      .compact.join(" ").presence
  end

  # type is 0..* CodeableConcept; index the first coding's code.
  def first_coding_code(concepts)
    coding = Array(concepts).first&.dig("coding")
    Array(coding).first&.dig("code")
  end
end
