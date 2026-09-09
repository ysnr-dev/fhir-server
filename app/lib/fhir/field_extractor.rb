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
  #
  # `fallback` (optional) is a second path tried only when `path` yields nil -- for a
  # choice element whose two forms feed one column (performedDateTime / performedPeriod.start).
  # `with` (optional) is a constant handed to the transform as its second argument
  # (e.g. the extension URLs :extension_datetime should look for).
  module FieldExtractor
    module_function

    def extract(resource, spec)
      value = dig_path(resource, spec[:path])
      value = dig_path(resource, spec[:fallback]) if value.nil? && spec[:fallback]
      transform = spec[:transform]
      return value unless transform

      spec.key?(:with) ? send(transform, value, spec[:with]) : send(transform, value)
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

    # FHIR `dateTime`: full ISO8601, or a partial date (YYYY, YYYY-MM, YYYY-MM-DD)
    # stored as UTC midnight of its first day -- search expands date-precision query
    # values to [Date, Date+1) intervals compared in UTC (see Search#parse_date_interval),
    # so this makes stored partial values line up exactly with those searches.
    # Returns a Time, or nil when blank/invalid.
    def datetime(value)
      return nil if value.blank?

      Time.iso8601(value)
    rescue ArgumentError, TypeError
      value.is_a?(String) ? partial_date(value)&.to_time(:utc) : nil
    end

    # The dateTime carried by the first extension (of a 0..* extension array) whose
    # url is one of `urls`, as valueDateTime / valueDate / valueInstant. nil when no
    # such extension exists or it carries no date value. Used for local extensions
    # that hold a date the base resource has no element for (an order's end date).
    def extension_datetime(extensions, urls)
      extension = Array(extensions).find do |element|
        element.is_a?(Hash) && urls.include?(element["url"])
      end
      return nil unless extension

      value = extension["valueDateTime"] || extension["valueDate"] || extension["valueInstant"]
      datetime(value)
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

    # First element of a 0..* array of primitive codes, e.g.
    # AllergyIntolerance.category: ["food", "medication"].
    def first_value(values)
      Array(values).first
    end

    # Human-readable text of a single CodeableConcept: concept.text plus the first
    # coding's display, space-joined; nil when both are absent.
    def concept_text(concept)
      concept ||= {}
      coding = Array(concept["coding"]).first
      [concept["text"], coding && coding["display"]].compact.join(" ").presence
    end

    # --- identifiers --------------------------------------------------------

    # First identifier's value of a 0..* Identifier array. Matching goes through
    # resource_identifiers (all identifiers); this flat column exists for _sort
    # (e.g. Organization departments ordered by department code).
    def first_identifier_value(identifiers)
      Array.wrap(identifiers).filter_map { |i| i.is_a?(Hash) ? i["value"].presence : nil }.first
    end

    # --- references ---------------------------------------------------------

    # First Patient reference among a 0..* backbone array whose elements each carry
    # a Reference at `actor` (Appointment.participant). Appointment has no
    # single-valued Patient element, but patient-compartment membership is derived
    # from single-valued indexed columns, so the patient among the participants is
    # flattened into one. An appointment listing two Patient participants keeps only
    # the first -- FHIR allows it, but no scheduling workflow here produces one.
    def actor_patient_reference(participants)
      Array(participants).filter_map do |participant|
        participant["actor"]["reference"] if participant.is_a?(Hash) && participant["actor"].is_a?(Hash)
      end.find { |reference| reference.is_a?(String) && reference.start_with?("Patient/") }
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

    # Every `name` across a 0..* backbone array that carries one (Device.deviceName),
    # space-joined -- the non-HumanName counterpart of all_name_representations.
    def name_list_text(elements)
      Array(elements).filter_map { |element| element["name"] if element.is_a?(Hash) }
                     .join(" ").presence
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
