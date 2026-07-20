class Organization < ApplicationRecord
  include FhirResourceRecord

  # Derives the search-optimized columns from the FHIR `content` payload.
  # Called before every persist so the extracted columns never drift from content.
  def sync_search_fields!
    resource = content || {}

    self.active = resource["active"]
    self.name = resource["name"]
    self.partof_reference = resource.dig("partOf", "reference")
  end
end
