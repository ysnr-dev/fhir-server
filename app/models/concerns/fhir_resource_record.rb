module FhirResourceRecord
  extend ActiveSupport::Concern

  # INVARIANT: the model's class name equals its FHIR resourceType (true for every
  # JP Core resource), so Rails' polymorphic `resource_type` column doubles as the
  # FHIR resourceType with no separate mapping.
  included do
    has_many :resource_identifiers, as: :resource, dependent: :destroy
    has_many :resource_tokens, as: :resource, dependent: :destroy
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

    # The declarative param_name -> token spec map (see Fhir::ExtractionDefinitions::*::TOKENS),
    # driving sync_tokens! via Fhir::TokenExtractor.
    def token_extraction_fields
      Fhir::ResourceRegistry.entry_for(polymorphic_name).fetch(:token_extraction)
    end

    # Additional identifier locations beyond the top-level `identifier` element
    # (see Fhir::ExtractionDefinitions::Practitioner::EXTRA_IDENTIFIERS). Most
    # resources have none.
    def extra_identifier_paths
      Fhir::ResourceRegistry.entry_for(polymorphic_name)[:extra_identifiers] || []
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

  # Rebuilds the resource_identifiers rows from content["identifier"] plus any
  # declared extra locations (e.g. Practitioner qualification identifiers). Array.wrap
  # (not Array()) so a 0..1 single-Identifier element (e.g. Composition.identifier)
  # is wrapped as one row rather than being splatted into [key, value] pairs.
  # Deduped by (system, value) so the same identifier written in two locations
  # (a transitional client habit) still yields a single searchable row.
  def sync_identifiers!
    resource_identifiers.destroy_all

    identifiers = Array.wrap(content["identifier"]) + extra_identifiers
    identifiers.uniq { |i| [i["system"], i["value"]] }.each do |identifier|
      next if identifier["value"].blank?

      resource_identifiers.create!(
        system: identifier["system"],
        value: identifier["value"]
      )
    end
  end

  # Identifier hashes gathered from the declared extra locations: for each spec,
  # every element of content[array_key] contributes its identifier_key entries
  # (an Identifier or array of Identifiers).
  def extra_identifiers
    self.class.extra_identifier_paths.flat_map do |spec|
      Array.wrap(content[spec[:array_key]]).flat_map do |element|
        element.is_a?(Hash) ? Array.wrap(element[spec[:identifier_key]]) : []
      end
    end.select { |i| i.is_a?(Hash) }
  end

  # Rebuilds the resource_tokens rows (one per coding, all codings) from content,
  # driven by the resource's declarative token map. Called alongside sync_identifiers!
  # so token search can match the full system|code pair.
  def sync_tokens!
    resource_tokens.destroy_all

    Fhir::TokenExtractor.rows(content, self.class.token_extraction_fields).each do |row|
      resource_tokens.create!(param_name: row[:param_name], system: row[:system], code: row[:code])
    end
  end
end
