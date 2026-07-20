class Patient < ApplicationRecord
  include FhirResourceRecord

  # Derives the search-optimized columns from the FHIR `content` payload.
  # Called before every persist so the extracted columns never drift from content.
  def sync_search_fields!
    resource = content || {}

    self.active = resource["active"]
    self.gender = resource["gender"]
    self.birth_date = parse_birth_date(resource["birthDate"])

    official_name = official_human_name(resource["name"])
    self.family = official_name&.dig("family")
    self.given = Array(official_name&.dig("given")).join(" ")
    self.name_text = all_name_representations(resource["name"]).join(" ")
  end

  private

  def official_human_name(names)
    return nil if names.blank?

    names.find { |n| n["use"] == "official" } || names.first
  end

  def all_name_representations(names)
    Array(names).flat_map do |name|
      [name["text"], name["family"], *Array(name["given"])]
    end.compact
  end

  def parse_birth_date(value)
    return nil if value.blank?

    Date.iso8601(value)
  rescue ArgumentError
    # birthDate may be a partial date (YYYY or YYYY-MM); fall back to year precision.
    begin
      Date.strptime(value, "%Y-%m")
    rescue ArgumentError
      begin
        Date.strptime(value, "%Y")
      rescue ArgumentError
        nil
      end
    end
  end
end
