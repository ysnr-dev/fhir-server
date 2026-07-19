class Organization < ApplicationRecord
  has_many :organization_identifiers, dependent: :destroy
  has_many :organization_versions, -> { order(version_id: :asc) }, dependent: :destroy

  # Derives the search-optimized columns from the FHIR `content` payload.
  # Called before every persist so the extracted columns never drift from content.
  def sync_search_fields!
    resource = content || {}

    self.active = resource["active"]
    self.name = resource["name"]
  end

  # Rebuilds the organization_identifiers rows from content["identifier"].
  def sync_identifiers!
    organization_identifiers.destroy_all

    Array(content["identifier"]).each do |identifier|
      next if identifier["value"].blank?

      organization_identifiers.create!(
        system: identifier["system"],
        value: identifier["value"]
      )
    end
  end
end
