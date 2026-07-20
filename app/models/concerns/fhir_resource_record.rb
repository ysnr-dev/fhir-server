module FhirResourceRecord
  extend ActiveSupport::Concern

  # INVARIANT: the model's class name equals its FHIR resourceType (true for every
  # JP Core resource), so Rails' polymorphic `resource_type` column doubles as the
  # FHIR resourceType with no separate mapping.
  included do
    has_many :resource_identifiers, as: :resource, dependent: :destroy
    has_many :resource_versions, -> { order(version_id: :asc) }, as: :resource, dependent: :destroy
  end

  class_methods do
    # The declarative column -> extraction spec map for this resource type, resolved
    # from the registry by polymorphic_name (== FHIR resourceType, per the invariant
    # above -- polymorphic_name defaults to the class name, but a model may override
    # it when the Ruby class name can't match the resourceType, e.g. InsuranceCoverage).
    def extraction_fields
      Fhir::ResourceRegistry.entry_for(polymorphic_name).fetch(:extraction)
    end
  end

  # Populates the search-optimized columns from the FHIR `content` payload, driven by
  # the resource's declarative extraction map (Fhir::ExtractionDefinitions, wired in
  # Fhir::ResourceRegistry) rather than a hand-written method per model. Called before
  # every persist so the extracted columns never drift from content.
  def sync_search_fields!
    resource = content || {}

    self.class.extraction_fields.each do |column, spec|
      self[column] = Fhir::FieldExtractor.extract(resource, spec)
    end
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
