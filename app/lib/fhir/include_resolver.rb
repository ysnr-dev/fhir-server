module Fhir
  # Resolves the `_include` (forward) and `_revinclude` (reverse) search
  # parameters into the extra resources that should be added to a searchset
  # Bundle with `search.mode = "include"`.
  #
  # It is a pure query object: given the current page of match records and the
  # normalized search params, it returns a de-duplicated array of ActiveRecord
  # instances to include. It never mutates the Bundle; BundleBuilder renders
  # the entries.
  class IncludeResolver
    def self.call(resource_type:, records:, search_params:)
      new(resource_type: resource_type, records: records, search_params: search_params).call
    end

    def initialize(resource_type:, records:, search_params:)
      @resource_type = resource_type
      # Materialize once: we scan the page multiple times (forward refs) and
      # BundleBuilder re-evaluates the relation separately for match entries.
      @records = records.to_a
      @search_params = search_params
    end

    # Bounds the :iterate expansion; combined with the seen-set below this
    # guards reference cycles (e.g. Location.partof chains) and runaway graphs.
    MAX_ITERATIONS = 5

    def call
      return [] if records.empty?

      # The base pass keys the match set by the DECLARED search type (a forward
      # include whose source is another type is ignored, per the guards below);
      # only the :iterate pass groups by each record's actual resourceType.
      base = { resource_type => records }
      included = dedup(forward(base, search_params.includes) +
                       reverse(base, search_params.revincludes))
      iterate(included)
    end

    private

    attr_reader :resource_type, :records, :search_params

    # :iterate directives re-apply to everything gathered so far (matches and
    # includes alike), repeating on each round's additions until nothing new
    # appears or MAX_ITERATIONS is reached.
    def iterate(included)
      inc_tokens = search_params.iterate_includes
      rev_tokens = search_params.iterate_revincludes
      return included if inc_tokens.empty? && rev_tokens.empty?

      seen = (records + included).to_h { |record| [dedup_key(record), true] }
      frontier = records + included

      MAX_ITERATIONS.times do
        by_type = records_by_type(frontier)
        additions = dedup(forward(by_type, inc_tokens) + reverse(by_type, rev_tokens))
                    .reject { |record| seen[dedup_key(record)] }
        break if additions.empty?

        additions.each { |record| seen[dedup_key(record)] = true }
        included += additions
        frontier = additions
      end

      included
    end

    # Groups by the FHIR resourceType in content (not the model class name,
    # which can differ -- e.g. InsuranceCoverage for Coverage).
    def records_by_type(list)
      list.group_by { |record| (record.content || {})["resourceType"] }
    end

    # Forward: for each source record, follow the reference at the mapped path
    # and load the target resources it points at. Tokens whose source type has
    # no records in `by_type` simply contribute nothing.
    def forward(by_type, tokens)
      tokens.flat_map do |token|
        info = SearchReferences.lookup(token)
        sources = info && by_type[info[:source_type]]
        next [] if sources.blank?

        definition = info[:definition]
        refs = collect_forward_refs(sources, definition)
        fetch_by_references(refs, definition[:targets], info[:target_type])
      end
    end

    def collect_forward_refs(sources, definition)
      sources.flat_map do |record|
        content = record.content || {}

        if definition[:multiple]
          Array(content[definition[:jsonb_key]]).filter_map do |element|
            element.dig(*definition[:ref_path]) if element.is_a?(Hash)
          end.select(&:present?)
        else
          value = content.dig(*definition[:path])
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
    # the given records. Only the record types the token's reference can target
    # participate.
    def reverse(by_type, tokens)
      tokens.flat_map do |token|
        info = SearchReferences.lookup(token)
        next [] unless info

        definition = info[:definition]
        target_types = definition[:targets] & by_type.keys
        next [] if target_types.empty?

        entry = ResourceRegistry.entry_for(info[:source_type])
        next [] unless entry

        refs = target_types.flat_map { |type| by_type[type].map { |record| "#{type}/#{record.id}" } }
        query_reverse(entry[:model], definition, refs).to_a
      end
    end

    def query_reverse(model, definition, refs)
      if definition[:multiple]
        # Multi-valued reference lives only in `content`; match array membership
        # via jsonb containment (GIN-indexed). OR over each candidate reference.
        scopes = refs.map do |ref|
          containment = { definition[:jsonb_key] => [nest(definition[:ref_path], ref)] }
          model.where(deleted: false).where("content @> ?", containment.to_json)
        end
        scopes.reduce(:or)
      else
        # Single-valued reference is extracted to an indexed column.
        model.where(deleted: false, definition[:column] => refs)
      end
    end

    # Builds the nested hash a jsonb containment query expects, e.g.
    # nest(["individual", "reference"], "Practitioner/1") => {"individual"=>{"reference"=>"Practitioner/1"}}
    def nest(path, value)
      path.reverse.reduce(value) { |acc, key| { key => acc } }
    end

    def dedup(list)
      seen = {}
      list.select do |record|
        key = dedup_key(record)
        next false if seen[key]

        seen[key] = true
      end
    end

    def dedup_key(record)
      [record.class.name, record.id]
    end
  end
end
