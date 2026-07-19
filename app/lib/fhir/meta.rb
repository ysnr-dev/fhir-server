module Fhir
  # Injects meta.versionId / meta.lastUpdated into a FHIR resource hash.
  module Meta
    module_function

    def apply(resource, version_id:, last_updated:)
      resource = resource.deep_dup
      resource["meta"] = (resource["meta"] || {}).merge(
        "versionId" => version_id.to_s,
        "lastUpdated" => last_updated.utc.iso8601(3)
      )
      resource
    end
  end
end
