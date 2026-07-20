module Fhir
  # Resolves the `_include` (forward) and `_revinclude` (reverse) search
  # parameters into the extra resources that should be added to a searchset
  # Bundle with `search.mode = "include"`.
  #
  # It is a pure query object: given the current page of match records and the
  # raw query params, it returns a de-duplicated array of ActiveRecord instances
  # to include. It never mutates the Bundle; BundleBuilder renders the entries.
  class IncludeResolver
    def self.call(resource_type:, records:, params:)
      new(resource_type: resource_type, records: records, params: params).call
    end

    def initialize(resource_type:, records:, params:)
      @resource_type = resource_type
      # Materialize once: we scan the page multiple times (forward refs) and
      # BundleBuilder re-evaluates the relation separately for match entries.
      @records = records.to_a
      @params = params
    end

    def call
      return [] if records.empty?

      dedup(resolve_includes + resolve_revincludes)
    end

    private

    attr_reader :resource_type, :records, :params

    # Forward: for each matched record, follow the reference at the mapped path
    # and load the target resources it points at.
    def resolve_includes
      tokens(params["_include"]).flat_map do |token|
        info = SearchReferences.lookup(token)
        # A forward include's source must be the type we are searching.
        next [] unless info && info[:source_type] == resource_type

        definition = info[:definition]
        refs = collect_forward_refs(definition)
        fetch_by_references(refs, definition[:targets], info[:target_type])
      end
    end

    def collect_forward_refs(definition)
      path = definition[:path]

      records.flat_map do |record|
        content = record.content || {}

        if definition[:multiple]
          key, sub = path
          Array(content[key]).filter_map { |el| el[sub] if el.is_a?(Hash) && el[sub].present? }
        else
          value = content.dig(*path)
          value.present? ? [value] : []
        end
      end
    end

    def fetch_by_references(refs, allowed_targets, target_filter)
      ids_by_type = Hash.new { |hash, key| hash[key] = [] }

      refs.uniq.each do |ref|
        type, id = ref.split("/", 2)
        next if type.blank? || id.blank?
        next unless allowed_targets.include?(type)
        next if target_filter && type != target_filter

        ids_by_type[type] << id
      end

      ids_by_type.flat_map do |type, ids|
        entry = ResourceRegistry.entry_for(type)
        next [] unless entry

        entry[:model].where(id: ids.uniq, deleted: false).to_a
      end
    end

    # Reverse: find the source resources whose reference points back at any of
    # the matched records.
    def resolve_revincludes
      refs = records.map { |record| "#{resource_type}/#{record.id}" }

      tokens(params["_revinclude"]).flat_map do |token|
        info = SearchReferences.lookup(token)
        next [] unless info

        definition = info[:definition]
        # A reverse include only makes sense when the source's reference can
        # point at the type we are searching.
        next [] unless definition[:targets].include?(resource_type)

        entry = ResourceRegistry.entry_for(info[:source_type])
        next [] unless entry

        query_reverse(entry[:model], definition, refs).to_a
      end
    end

    def query_reverse(model, definition, refs)
      if definition[:multiple]
        # Multi-valued reference lives only in `content`; match array membership
        # via jsonb containment (GIN-indexed). OR over each candidate reference.
        scopes = refs.map do |ref|
          model.where(deleted: false).where("content @> ?", { definition[:jsonb_key] => [{ "reference" => ref }] }.to_json)
        end
        scopes.reduce(:or)
      else
        # Single-valued reference is extracted to an indexed column.
        model.where(deleted: false, definition[:column] => refs)
      end
    end

    def tokens(value)
      Array(value).flat_map { |token| token.to_s.split(",") }.map(&:strip).reject(&:blank?)
    end

    def dedup(list)
      seen = {}
      list.select do |record|
        key = [record.class.name, record.id]
        next false if seen[key]

        seen[key] = true
      end
    end
  end
end
