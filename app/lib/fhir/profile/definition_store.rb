require "set"

module Fhir
  module Profile
    # Lazily loads and memoizes the vendored JP Core StructureDefinitions,
    # ValueSets, and CodeSystems written by `rake jp_core:vendor` into
    # vendor/jp_core/ (see lib/tasks/jp_core.rake). The app never fetches
    # anything over the network at runtime -- only these committed files.
    #
    # A single Mutex guards all cache reads/writes because Puma runs multiple
    # threads per worker; the mutex is not reentrant, so every public method
    # takes the lock exactly once at its entry point and the private helpers
    # below never take it again, even when they recurse (e.g. an expansion
    # that references a nested ValueSet).
    module DefinitionStore
      VENDOR_ROOT = Rails.root.join("vendor", "jp_core")

      module_function

      def structure_definition(url)
        with_lock { fetch_definition(:structure_definitions, canonical(url)) }
      end

      def value_set(url)
        with_lock { fetch_definition(:value_sets, canonical(url)) }
      end

      def code_system(url)
        with_lock { fetch_definition(:code_systems, canonical(url)) }
      end

      def known_profile?(url)
        with_lock { index[:structure_definitions].key?(canonical(url)) }
      end

      # Flattens a ValueSet's `compose.include` into a Set of allowed codes.
      # Returns nil (the caller should skip the binding check) when the
      # ValueSet itself isn't vendored, an include uses a `filter` we don't
      # evaluate, or an include references a system/nested ValueSet we don't
      # have -- any of those mean we cannot claim exhaustive knowledge of the
      # expansion, and a false "not in value set" rejection would be worse
      # than not checking at all.
      def expansion(value_set_url)
        with_lock { fetch_expansion(canonical(value_set_url)) }
      end

      # --- internals (assume the lock is already held) ------------------------

      def with_lock
        mutex.synchronize { yield }
      end
      private_class_method :with_lock

      def mutex
        @mutex ||= Mutex.new
      end
      private_class_method :mutex

      def canonical(url)
        url.to_s.split("|").first
      end
      private_class_method :canonical

      def index
        @index ||= load_index
      end
      private_class_method :index

      def load_index
        path = VENDOR_ROOT.join("index.json")
        return { structure_definitions: {}, value_sets: {}, code_systems: {} } unless File.exist?(path)

        raw = JSON.parse(File.read(path))
        {
          structure_definitions: raw.fetch("structure_definitions", {}),
          value_sets: raw.fetch("value_sets", {}),
          code_systems: raw.fetch("code_systems", {})
        }
      end
      private_class_method :load_index

      def cache
        @cache ||= { structure_definitions: {}, value_sets: {}, code_systems: {}, expansions: {} }
      end
      private_class_method :cache

      def fetch_definition(kind, url)
        return cache[kind][url] if cache[kind].key?(url)

        relative_path = index[kind][url]
        cache[kind][url] = relative_path ? JSON.parse(File.read(VENDOR_ROOT.join(relative_path))) : nil
      end
      private_class_method :fetch_definition

      def fetch_expansion(value_set_url)
        return cache[:expansions][value_set_url] if cache[:expansions].key?(value_set_url)

        cache[:expansions][value_set_url] = compute_expansion(value_set_url)
      end
      private_class_method :fetch_expansion

      def compute_expansion(value_set_url)
        definition = fetch_definition(:value_sets, value_set_url)
        return nil unless definition

        codes = Set.new
        Array(definition.dig("compose", "include")).each do |include_entry|
          entry_codes = expand_include(include_entry)
          return nil unless entry_codes

          codes.merge(entry_codes)
        end
        codes
      end
      private_class_method :compute_expansion

      def expand_include(include_entry)
        return nil if include_entry.key?("filter")

        if include_entry["concept"]
          Array(include_entry["concept"]).map { |c| c["code"] }
        elsif include_entry["system"]
          code_system_codes(canonical(include_entry["system"]))
        elsif include_entry["valueSet"]
          merge_nested_value_sets(include_entry["valueSet"])
        end
      end
      private_class_method :expand_include

      def merge_nested_value_sets(value_set_urls)
        codes = Set.new
        Array(value_set_urls).each do |nested_url|
          nested = fetch_expansion(canonical(nested_url))
          return nil unless nested

          codes.merge(nested)
        end
        codes
      end
      private_class_method :merge_nested_value_sets

      def code_system_codes(url)
        definition = fetch_definition(:code_systems, url)
        return nil unless definition

        flatten_concepts(definition["concept"])
      end
      private_class_method :code_system_codes

      def flatten_concepts(concepts)
        Array(concepts).each_with_object(Set.new) do |concept, set|
          set << concept["code"]
          set.merge(flatten_concepts(concept["concept"])) if concept["concept"]
        end
      end
      private_class_method :flatten_concepts
    end
  end
end
