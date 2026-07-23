module Fhir
  # Turns a resource's declarative token map (Fhir::ExtractionDefinitions::*::TOKENS,
  # keyed by canonical search-param name) into the (system, code) rows that populate
  # resource_tokens. Unlike Fhir::FieldExtractor -- which flattens each element to a
  # single search column -- this emits EVERY coding of a CodeableConcept, so a resource
  # coded in both LOINC and a local system is findable by either.
  #
  # `kind` classifies the shape at `path`:
  #   :code                    primitive code           -> [(nil, code)]
  #   :code_list               0..* primitive codes     -> one row per entry
  #   :codeable_concept        0..1 CodeableConcept      -> one row per coding
  #   :codeable_concept_list   0..* CodeableConcept      -> one row per coding, all concepts
  #   :coding                  0..1 bare Coding          -> [(system, code)]
  #   :coding_list             0..* bare Coding          -> one row per coding
  #   :identifier              0..1 Identifier           -> [(identifier.system, identifier.value)]
  module TokenExtractor
    module_function

    # Returns [{ param_name:, system:, code: }, ...]; rows with a blank code are dropped
    # and a blank system is normalized to nil (so `|code` can match "no system").
    def rows(content, tokens_spec)
      resource = content || {}

      tokens_spec.flat_map do |param_name, spec|
        node = dig_path(resource, spec[:path])
        pairs(node, spec[:kind]).filter_map do |system, code|
          next if code.blank?

          { param_name: param_name.to_s, system: system.presence, code: code }
        end
      end
    end

    def dig_path(resource, path)
      path.to_s.split(".").reduce(resource) do |node, key|
        node.is_a?(Hash) ? node[key] : nil
      end
    end

    # Returns an array of [system, code] pairs for the node at `path`, per `kind`.
    def pairs(node, kind)
      case kind
      when :code                  then node.is_a?(String) ? [[nil, node]] : []
      when :code_list             then Array(node).select { |c| c.is_a?(String) }.map { |c| [nil, c] }
      when :codeable_concept      then concept_codings(node)
      when :codeable_concept_list then Array(node).flat_map { |cc| concept_codings(cc) }
      when :coding                then coding_pair(node)
      when :coding_list           then Array(node).flat_map { |c| coding_pair(c) }
      when :identifier            then node.is_a?(Hash) ? [[node["system"], node["value"]]] : []
      else []
      end
    end

    def concept_codings(concept)
      return [] unless concept.is_a?(Hash)

      Array(concept["coding"]).flat_map { |c| coding_pair(c) }
    end

    def coding_pair(coding)
      coding.is_a?(Hash) ? [[coding["system"], coding["code"]]] : []
    end
  end
end
