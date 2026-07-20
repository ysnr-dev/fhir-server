module FhirResourceRecord
  extend ActiveSupport::Concern

  # INVARIANT: the model's class name equals its FHIR resourceType (true for every
  # JP Core resource), so Rails' polymorphic `resource_type` column doubles as the
  # FHIR resourceType with no separate mapping.
  included do
    has_many :resource_identifiers, as: :resource, dependent: :destroy
    has_many :resource_versions, -> { order(version_id: :asc) }, as: :resource, dependent: :destroy
  end

  # Rebuilds the resource_identifiers rows from content["identifier"].
  def sync_identifiers!
    resource_identifiers.destroy_all

    Array(content["identifier"]).each do |identifier|
      next if identifier["value"].blank?

      resource_identifiers.create!(
        system: identifier["system"],
        value: identifier["value"]
      )
    end
  end
end
