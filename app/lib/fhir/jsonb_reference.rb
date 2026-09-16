module Fhir
  # Plumbing shared by every reader of a 0..* reference element that lives only in
  # `content` (no extracted column): the jsonb containment shapes a query needs,
  # and the reference strings a stored element holds. Used by Search (reference
  # params, _has, :missing) and IncludeResolver (_include / _revinclude).
  #
  # A definition names the element with :jsonb_key (the array's key in content) and
  # :ref_path (path to the reference string inside one element). Two optional keys
  # narrow it: :element_match pins constant keys on the same element (an
  # extension's `url` -- without it a parameter reading `extension[].valueReference`
  # would also match a DIFFERENT extension carrying the same reference, since
  # containment only asks "is there an element like this"), and :nested_path names
  # array keys INSIDE the element for parameters whose target sits one array deeper
  # (Composition.section[].entry[]).
  module JsonbReference
    module_function

    # The nested hash a jsonb containment query expects, e.g.
    # nest(["individual", "reference"], "Practitioner/1") => {"individual"=>{"reference"=>"Practitioner/1"}}
    def nest(path, value)
      path.reverse.reduce(value) { |acc, key| { key => acc } }
    end

    # One element of the array as it appears in a containment query. :nested_path
    # wraps from the inside out ({"entry"=>[{"reference"=>ref}]}); :element_match
    # is merged onto the outermost element, so it still pins the outer array's element.
    def containment_element(definition, ref)
      element = Array(definition[:nested_path]).reverse.reduce(nest(definition[:ref_path], ref)) do |acc, key|
        { key => [acc] }
      end
      definition[:element_match] ? element.merge(definition[:element_match]) : element
    end

    # The JSON document for `content @> ?` matching one reference.
    def containment(definition, ref)
      { definition[:jsonb_key] => [containment_element(definition, ref)] }.to_json
    end

    # The same element with the reference left out: "an element of this kind
    # exists at all", used by :missing. An empty array is contained in any array,
    # so {"section":[{"entry":[]}]} reads as "is there a section that HAS an entry
    # array" -- which is what :missing needs when the outer key alone says nothing.
    def presence_containment(definition)
      element = definition[:element_match] || {}
      element = element.merge(definition[:nested_path].first => []) if definition[:nested_path]
      { definition[:jsonb_key] => [element] }.to_json
    end

    # Every reference string the element's array holds in `content`.
    def refs_in(content, definition)
      Array(content[definition[:jsonb_key]]).flat_map { |element| element_refs(element, definition) }
    end

    # The reference strings held by one element of the array: nothing when
    # :element_match rules the element out, else the value at :ref_path of the
    # element itself or (with :nested_path) of each node one array deeper.
    def element_refs(element, definition)
      return [] unless element.is_a?(Hash)

      match = definition[:element_match]
      return [] if match && match.any? { |key, value| element[key] != value }

      inner = Array(definition[:nested_path]).reduce([element]) do |acc, key|
        acc.flat_map { |node| Array(node[key]) }
      end
      inner.filter_map { |node| node.dig(*definition[:ref_path]) if node.is_a?(Hash) }.reject(&:blank?)
    end
  end
end
