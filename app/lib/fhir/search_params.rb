module Fhir
  # Parses a raw HTTP query string into an ordered list of normalized search
  # clauses, preserving repeated parameter occurrences (AND) and comma-joined
  # values (OR) that Rack::Utils.parse_nested_query / request.query_parameters
  # collapse to last-wins. Fhir::Search, IncludeResolver, and BundleBuilder all
  # consume this instead of a plain params Hash.
  class SearchParams
    Clause = Struct.new(:name, :modifier, :values, keyword_init: true) do
      Chain = Struct.new(:base, :target_type, :param, :tail_modifier, keyword_init: true)
      Has = Struct.new(:source_type, :ref_param, :param, :tail_modifier, keyword_init: true)

      # Interprets this clause as a chained reference search, or nil. The parser
      # splits the raw key at the FIRST ":", so the four accepted shapes arrive as:
      #   subject.name               -> name="subject.name",  modifier=nil
      #   subject.name:exact         -> name="subject.name",  modifier="exact"
      #   subject:Patient.name       -> name="subject",       modifier="Patient.name"
      #   subject:Patient.name:exact -> name="subject",       modifier="Patient.name:exact"
      # name/modifier stay untouched, so serialize_clause round-trips chains as-is.
      def chain
        if name.include?(".") && !name.start_with?("_")
          base, _, param = name.partition(".")
          Chain.new(base: base, target_type: nil, param: param, tail_modifier: modifier)
        elsif modifier&.include?(".")
          typed, _, tail_modifier = modifier.partition(":")
          target_type, _, param = typed.partition(".")
          Chain.new(base: name, target_type: target_type, param: param, tail_modifier: tail_modifier.presence)
        end
      end

      # Interprets this clause as a reverse chain, or nil:
      #   _has:Observation:patient:code       -> name="_has", modifier="Observation:patient:code"
      #   _has:Observation:patient:code:exact -> tail modifier on the chained param
      def has
        return nil unless name == "_has" && modifier.present?

        source_type, ref_param, rest = modifier.split(":", 3)
        return nil if source_type.blank? || ref_param.blank? || rest.blank?

        param, _, tail_modifier = rest.partition(":")
        Has.new(source_type: source_type, ref_param: ref_param, param: param, tail_modifier: tail_modifier.presence)
      end
    end

    META_NAMES = %w[_sort _count _offset _include _revinclude _summary _elements _total].freeze

    def self.parse(query_string)
      new(parse_pairs(query_string))
    end

    # Bridge for call sites still passing a Hash (Rails params-style). A Hash
    # cannot represent two occurrences of the same key with different values,
    # so this is a lossy convenience for tests/staged migration, not a
    # replacement for .parse.
    def self.from_hash(hash)
      new(hash.flat_map { |key, value| pairs_from_hash_entry(key, value) })
    end

    def self.parse_pairs(query_string)
      query_string.to_s.sub(/\A\?/, "").split("&").filter_map do |pair|
        key, _, raw_value = pair.partition("=")
        next if key.empty?

        name, _, modifier = Rack::Utils.unescape(key).partition(":")
        modifier = nil if modifier.empty?

        Clause.new(name: name, modifier: modifier, values: split_values(Rack::Utils.unescape(raw_value)))
      end
    end
    private_class_method :parse_pairs

    def self.pairs_from_hash_entry(raw_key, raw_value)
      key = raw_key.to_s
      name, _, modifier = key.partition(":")
      modifier = nil if modifier.empty?

      Array(raw_value).map do |value|
        Clause.new(name: name, modifier: modifier, values: split_values(value.to_s))
      end
    end
    private_class_method :pairs_from_hash_entry

    def self.split_values(raw_value)
      raw_value.empty? ? [""] : raw_value.split(",", -1)
    end
    private_class_method :split_values

    def initialize(all_clauses)
      @all_clauses = all_clauses
      @clauses = all_clauses.reject { |c| META_NAMES.include?(c.name) }
    end

    attr_reader :clauses

    def clauses_for(name)
      clauses.select { |c| c.name == name }
    end

    def sort
      last_unmodified_value("_sort")
    end

    def count
      last_unmodified_value("_count")
    end

    def offset
      last_unmodified_value("_offset")
    end

    def summary
      last_unmodified_value("_summary")
    end

    def elements
      unmodified_clauses("_elements").flat_map(&:values).reject(&:blank?)
    end

    def total_mode
      last_unmodified_value("_total")
    end

    def includes
      unmodified_clauses("_include").flat_map(&:values)
    end

    def revincludes
      unmodified_clauses("_revinclude").flat_map(&:values)
    end

    # Rebuilds a query string from the normalized clauses so pagination links
    # round-trip repeated params and modifiers instead of losing them through
    # Hash#to_query. Non-meta clauses keep their original relative order;
    # meta params are re-emitted in a fixed order with `_offset` last.
    def to_query(offset:)
      parts = clauses.map { |c| serialize_clause(c) }
      parts << "_sort=#{escape(sort)}" if sort.present?
      parts << "_count=#{escape(count)}" if count.present?
      parts << "_summary=#{escape(summary)}" if summary.present?
      parts << "_elements=#{elements.map { |e| escape(e) }.join(',')}" if elements.any?
      parts << "_total=#{escape(total_mode)}" if total_mode.present?
      parts.concat(unmodified_clauses("_include").map { |c| serialize_clause(c) })
      parts.concat(unmodified_clauses("_revinclude").map { |c| serialize_clause(c) })
      parts << "_offset=#{offset}"
      parts.join("&")
    end

    private

    def unmodified_clauses(name)
      @all_clauses.select { |c| c.name == name && c.modifier.nil? }
    end

    # _sort's value is itself a comma-joined list (e.g. "family,birthdate") whose
    # internal structure the caller (Fhir::Search) re-splits -- so the full value
    # must be rejoined here, not truncated to the first comma-split token.
    def last_unmodified_value(name)
      unmodified_clauses(name).last&.values&.join(",")
    end

    def serialize_clause(clause)
      key = clause.modifier ? "#{escape(clause.name)}:#{escape(clause.modifier)}" : escape(clause.name)
      "#{key}=#{clause.values.map { |v| escape(v) }.join(',')}"
    end

    def escape(value)
      Rack::Utils.escape(value.to_s)
    end
  end
end
