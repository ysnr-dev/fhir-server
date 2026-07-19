class MedicationRequest < ApplicationRecord
  has_many :medication_request_identifiers, dependent: :destroy
  has_many :medication_request_versions, -> { order(version_id: :asc) }, dependent: :destroy

  # Derives the search-optimized columns from the FHIR `content` payload.
  # Called before every persist so the extracted columns never drift from content.
  def sync_search_fields!
    resource = content || {}

    self.status = resource["status"]
    self.intent = resource["intent"]
    self.subject_reference = resource.dig("subject", "reference")
    self.authored_on = parse_authored_on(resource["authoredOn"])

    medication = resource["medicationCodeableConcept"] || {}
    coding = Array(medication["coding"]).first
    self.medication_code = coding && coding["code"]
    self.medication_text = [medication["text"], coding && coding["display"]].compact.join(" ").presence
  end

  # Rebuilds the medication_request_identifiers rows from content["identifier"].
  def sync_identifiers!
    medication_request_identifiers.destroy_all

    Array(content["identifier"]).each do |identifier|
      next if identifier["value"].blank?

      medication_request_identifiers.create!(
        system: identifier["system"],
        value: identifier["value"]
      )
    end
  end

  private

  def parse_authored_on(value)
    return nil if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end
end
