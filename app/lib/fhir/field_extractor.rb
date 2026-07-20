module Fhir
  # Turns a declarative extraction spec ({ path:, transform: }) into the value that
  # populates a resource's search column. Centralizes every extraction transform that
  # used to be copy-pasted across the model `sync_search_fields!` methods, so a new
  # resource declares its column mappings (see Fhir::ExtractionDefinitions) rather than
  # hand-writing extraction code.
  #
  # `path` is a dot-separated route into the FHIR `content` hash ("subject.reference",
  # "class.code", "birthDate"); a nil/non-hash step yields nil. `transform` (optional)
  # names one of the methods below, applied to the value at `path`. With no transform,
  # the raw value at `path` is returned (scalars, references, plain digs).
  module FieldExtractor
    module_function

    def extract(resource, spec)
      value = dig_path(resource, spec[:path])
      transform = spec[:transform]
      transform ? send(transform, value) : value
    end

    def dig_path(resource, path)
      path.to_s.split(".").reduce(resource) do |node, key|
        node.is_a?(Hash) ? node[key] : nil
      end
    end

    # --- date / time --------------------------------------------------------

    # FHIR `date`, possibly partial: full ISO8601, then YYYY-MM (day -> 1), then
    # YYYY (month/day -> 1). Returns a Date, or nil when unparseable/blank.
    def partial_date(value)
      return nil if value.blank?

      Date.iso8601(value)
    rescue ArgumentError
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

    # FHIR `dateTime`: ISO8601 with timezone. Returns a Time, or nil when blank/invalid.
    def datetime(value)
      return nil if value.blank?

      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end

    # --- codings ------------------------------------------------------------

    # First coding's code of a single (0..1) CodeableConcept, e.g.
    # medicationCodeableConcept: { coding: [{ code: "..." }] }.
    def coding_code(concept)
      coding = Array((concept || {})["coding"]).first
      coding && coding["code"]
    end

    # First coding's code of the first concept in a 0..* array of CodeableConcepts,
    # e.g. code: [{ coding: [{ code: "..." }] }] (PractitionerRole.code, Location.type).
    def concept_list_code(concepts)
      coding = Array(concepts).first&.dig("coding")
      Array(coding).first&.dig("code")
    end

    # First code of a 0..* array of bare Codings (not CodeableConcepts), e.g.
    # ImagingStudy.modality: [{ system: "...", code: "CT" }].
    def coding_list_code(codings)
      Array(codings).first&.dig("code")
    end

    # Human-readable text of a single CodeableConcept: concept.text plus the first
    # coding's display, space-joined; nil when both are absent.
    def concept_text(concept)
      concept ||= {}
      coding = Array(concept["coding"]).first
      [concept["text"], coding && coding["display"]].compact.join(" ").presence
    end

    # --- HumanName ----------------------------------------------------------

    # family of the official name (or the first name when none is marked official).
    def official_family(names)
      official_name(names)&.dig("family")
    end

    # given names of the official name, space-joined ("" when present but no given).
    def official_given(names)
      Array(official_name(names)&.dig("given")).join(" ")
    end

    # Every text/family/given token across ALL name entries (official + kana/alias),
    # space-joined -- so kana representations land in name_text but not family/given.
    def all_name_representations(names)
      Array(names).flat_map do |name|
        [name["text"], name["family"], *Array(name["given"])]
      end.compact.join(" ")
    end

    def official_name(names)
      return nil if names.blank?

      names.find { |n| n["use"] == "official" } || names.first
    end

    # --- Address ------------------------------------------------------------

    # Flattens a single Address into a searchable string in a fixed field order:
    # text, each line, city, state, postalCode. nil when empty.
    def address_text(address)
      return nil if address.blank?

      [address["text"], *Array(address["line"]), address["city"], address["state"], address["postalCode"]]
        .compact.join(" ").presence
    end
  end
end
