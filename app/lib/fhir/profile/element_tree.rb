module Fhir
  module Profile
    # Converts a trimmed StructureDefinition (see lib/tasks/jp_core.rake) into
    # a tree of Node objects that Validator walks against a resource payload.
    #
    # FHIR snapshots are a flat list of elements identified by a dotted `id`
    # (not `path` -- `id` is the only field that carries slice scoping, e.g.
    # "MedicationRequest.identifier:rpNumber.system" vs the shared path
    # "MedicationRequest.identifier.system"). Every element's parent is found
    # by dropping its last dotted segment; a segment written as "name:slice"
    # attaches the element to the *sibling* slicing-definition element's
    # `slices` array instead of becoming a plain child, since both represent
    # the same array slot ("identifier") at different specificity.
    module ElementTree
      Node = Struct.new(
        :id, :path, :name, :slice_name, :min, :max, :base_max, :types, :binding,
        :fixed, :pattern, :slicing, :content_reference, :children, :slices, :discriminator,
        keyword_init: true
      )

      module_function

      # Memoized per StructureDefinition object identity -- callers (Validator)
      # are expected to pass the same Hash instance back for a given profile
      # URL, since DefinitionStore itself already memoizes the parsed JSON.
      def build(structure_definition)
        cache[structure_definition.object_id] ||= build_tree(structure_definition)
      end

      def cache
        @cache ||= {}
      end
      private_class_method :cache

      def build_tree(structure_definition)
        elements = Array(structure_definition.dig("snapshot", "element"))
        return nil if elements.empty?

        index_by_id = {}
        elements.each { |element| index_by_id[element["id"]] = node_for(element) }

        root_id = structure_definition["type"] || elements.first["id"]
        root = index_by_id[root_id]
        return nil unless root

        elements.each do |element|
          attach(element, index_by_id)
        end

        resolve_discriminators(index_by_id)
        root
      end
      private_class_method :build_tree

      def node_for(element)
        last_segment = element["id"].to_s.split(".").last.to_s
        name, slice_name = last_segment.include?(":") ? last_segment.split(":", 2) : [last_segment, nil]

        fixed_key = element.keys.find { |k| k.start_with?("fixed") }
        pattern_key = element.keys.find { |k| k.start_with?("pattern") }

        Node.new(
          id: element["id"],
          path: element["path"],
          name: name,
          slice_name: slice_name,
          min: element["min"],
          max: element["max"],
          base_max: element.dig("base", "max") || element["max"],
          types: Array(element["type"]),
          binding: element["binding"],
          fixed: fixed_key && { key: fixed_key, value: element[fixed_key] },
          pattern: pattern_key && { key: pattern_key, value: element[pattern_key] },
          slicing: element["slicing"],
          content_reference: element["contentReference"],
          children: {},
          slices: [],
          discriminator: nil
        )
      end
      private_class_method :node_for

      def attach(element, index_by_id)
        id = element["id"].to_s
        return unless id.include?(".") # root has no parent

        parent_id, _sep, last_segment = id.rpartition(".")
        name, slice_name = last_segment.include?(":") ? last_segment.split(":", 2) : [last_segment, nil]
        this_node = index_by_id[id]

        if slice_name
          # The sibling "slicing definition" element (no slice suffix) always
          # exists per the FHIR snapshot generator's contract; skip silently
          # if a malformed/unexpected snapshot violates that.
          base_node = index_by_id["#{parent_id}.#{name}"]
          base_node&.slices&.push(this_node)
        else
          parent_node = index_by_id[parent_id]
          parent_node&.children&.[]=(name, this_node)
        end
      end
      private_class_method :attach

      # Precomputes, for every slice, the {path:, value:} pairs its
      # discriminator(s) must match. A discriminator value is resolved from
      # (a) a fixed/pattern value on the slice's own local descendant element
      # (covers e.g. identifier slicing by `system`), or (b) for the
      # well-known FHIR extension-slicing convention (discriminator path
      # "url", slice type "Extension" with a declared profile), the
      # extension's own canonical URL -- Extension.url is always fixed to it
      # by definition, so we don't need to open the extension's own SD just
      # to confirm that. A discriminator we can't resolve either way is left
      # nil, and Validator treats that slice as unmatchable (skips bucketing
      # it, never blocks the rest of the array).
      # Sets each slice's `discriminator` to a resolved [{path:, value:}, ...]
      # list only when EVERY declared discriminator is both a "value"-type
      # discriminator (the only kind this engine supports) and successfully
      # resolved (see #resolve_one). Otherwise it's set to nil, meaning
      # "unmatchable" -- Validator must never treat that as an empty (i.e.
      # vacuously-true, matches-everything) match list.
      def resolve_discriminators(index_by_id)
        index_by_id.each_value do |node|
          next if node.slicing.nil? || node.slices.empty?

          raw = Array(node.slicing["discriminator"])
          value_discriminators = raw.select { |d| d["type"] == "value" }

          node.slices.each do |slice|
            if value_discriminators.size != raw.size
              slice.discriminator = nil
              next
            end

            resolved = value_discriminators.filter_map { |d| resolve_one(slice, d["path"], index_by_id) }
            slice.discriminator = resolved.size == value_discriminators.size ? resolved : nil
          end
        end
      end
      private_class_method :resolve_discriminators

      def resolve_one(slice, discriminator_path, index_by_id)
        local = index_by_id["#{slice.id}.#{discriminator_path}"]
        if local && (local.fixed || local.pattern)
          value = (local.fixed || local.pattern)[:value]
          return { path: discriminator_path, value: value }
        end

        if discriminator_path == "url" && slice.types.any? { |t| t["code"] == "Extension" }
          profile_url = slice.types.first["profile"]&.first
          return { path: discriminator_path, value: profile_url.split("|").first } if profile_url
        end

        nil
      end
      private_class_method :resolve_one
    end
  end
end
