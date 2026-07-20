class ServiceRequest < ApplicationRecord
  include FhirResourceRecord

  # Derives the search-optimized columns from the FHIR `content` payload.
  # Called before every persist so the extracted columns never drift from content.
  def sync_search_fields!
    resource = content || {}

    self.status = resource["status"]
    self.intent = resource["intent"]
    self.subject_reference = resource.dig("subject", "reference")
    self.encounter_reference = resource.dig("encounter", "reference")
    self.requester_reference = resource.dig("requester", "reference")
    self.authored_on = parse_authored_on(resource["authoredOn"])

    code_concept = resource["code"] || {}
    coding = Array(code_concept["coding"]).first
    self.code = coding && coding["code"]
    self.code_text = [code_concept["text"], coding && coding["display"]].compact.join(" ").presence
  end

  private

  def parse_authored_on(value)
    return nil if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end
end
