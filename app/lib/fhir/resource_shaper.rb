module Fhir
  # Shapes search-result resources for _summary / _elements: slices the resource
  # to the requested elements and marks it SUBSETTED. Applied AFTER Meta.apply
  # (so meta always exists and the tag survives), one instance per request.
  #
  # Modes:
  #   _summary=text  -> resourceType/id/meta/text only
  #   _summary=data  -> everything except text
  #   _elements=a,b  -> mandatory keys + the requested top-level elements
  #                     (only when no _summary is active; _summary wins per spec)
  # _summary=count is handled upstream (no entries at all); _summary=true would
  # need the per-resource summary-element tables from the FHIR definitions
  # (ElementDefinition.isSummary), so it is not supported and ignored -- noted
  # as a follow-up.
  class ResourceShaper
    SUBSETTED_TAG = {
      "system" => "http://terminology.hl7.org/CodeSystem/v3-ObservationValue",
      "code" => "SUBSETTED"
    }.freeze

    MANDATORY = %w[resourceType id meta].freeze

    # Returns a shaper, or nil when no shaping applies.
    def self.build(search_params)
      case search_params.summary
      when "text" then new(keep: MANDATORY + %w[text])
      when "data" then new(drop: %w[text])
      when nil, ""
        elements = search_params.elements
        elements.any? ? new(keep: MANDATORY + elements) : nil
      end
    end

    def initialize(keep: nil, drop: nil)
      @keep = keep&.uniq
      @drop = drop
    end

    def call(resource)
      shaped = @keep ? resource.slice(*@keep) : resource.except(*@drop)
      subsetted(shaped)
    end

    private

    def subsetted(resource)
      meta = (resource["meta"] || {}).dup
      tags = Array(meta["tag"])
      unless tags.any? { |tag| tag["system"] == SUBSETTED_TAG["system"] && tag["code"] == SUBSETTED_TAG["code"] }
        meta["tag"] = tags + [SUBSETTED_TAG]
      end
      resource.merge("meta" => meta)
    end
  end
end
