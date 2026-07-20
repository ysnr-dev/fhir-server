class Encounter < ApplicationRecord
  include FhirResourceRecord

  # Derives the search-optimized columns from the FHIR `content` payload.
  # Called before every persist so the extracted columns never drift from content.
  def sync_search_fields!
    resource = content || {}

    self.status = resource["status"]
    self.class_code = resource.dig("class", "code")
    self.subject_reference = resource.dig("subject", "reference")
    self.period_start = parse_time(resource.dig("period", "start"))
  end

  private

  def parse_time(value)
    return nil if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end
end
