module Fhir
  # Injects meta.versionId / meta.lastUpdated / meta.profile into a FHIR resource
  # hash at render time (not persisted -- Fhir::Repository strips client-supplied
  # meta on write). meta.profile is resolved from Fhir::ResourceRegistry rather
  # than stored, so a profile URL change (e.g. a JP Core version bump) applies to
  # every resource, including past versions rendered via _history/vread, without
  # a data migration.
  module Meta
    module_function

    def apply(resource, version_id:, last_updated:)
      resource = resource.deep_dup
      meta = {
        "versionId" => version_id.to_s,
        "lastUpdated" => last_updated.utc.iso8601(3)
      }
      profile = ResourceRegistry.entry_for(resource["resourceType"])&.fetch(:profile, nil)
      meta["profile"] = [profile] if profile

      resource["meta"] = (resource["meta"] || {}).merge(meta)
      resource
    end
  end
end
