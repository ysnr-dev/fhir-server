module Fhir
  # Executes a FHIR search against a single resource type, driven by the declarative
  # parameter definitions registered per type (see Fhir::SearchDefinitions::*) instead
  # of a hand-written search class per resource.
  #
  # Consumes a Fhir::SearchParams (normalized clauses) rather than a raw params Hash,
  # so repeated parameters (AND) and comma-joined values (OR) are both supported. Each
  # clause is combined into the scope as ONE SQL fragment with its values OR-joined
  # inside, and AND-ed across clauses -- this sidesteps ActiveRecord#or's requirement
  # that both sides of an OR be structurally identical relations.
  class Search
    DEFAULT_COUNT = 20
    MAX_COUNT = 100

    # sa (starts-after) / eb (ends-before) / ap (approximately) are recognized so they
    # don't fall through to the no-prefix (eq) case, but are not implemented -- a clause
    # using them is silently skipped (lenient), same as an unparseable date value.
    DATE_PREFIX_PATTERN = /\A(eq|ne|ge|le|gt|lt|sa|eb|ap)(\d.*)\z/.freeze
    SUPPORTED_DATE_PREFIXES = %w[eq ne ge le gt lt].freeze

    STRING_MODIFIERS = %w[exact contains].freeze

    # _id and _lastUpdated behave like any other search param (comma-OR, repeat-AND)
    # rather than being handled as special cases.
    SYSTEM_PARAMS = {
      "_id" => { type: :token, column: :id },
      "_lastUpdated" => { type: :datetime, column: :last_updated }
    }.freeze

    Result = Struct.new(:records, :total, :count, :offset, keyword_init: true)

    def self.call(resource_type, search_params)
      new(resource_type, search_params).call
    end

    def initialize(resource_type, search_params)
      entry = ResourceRegistry.entry_for(resource_type)
      @resource_type = resource_type
      @model = entry.fetch(:model)
      @search_param_defs = entry.fetch(:search_params)
      @search_params = search_params
    end

    def call
      scope = model.where(deleted: false)

      search_params.clauses.each do |clause|
        definition = definition_for(clause.name)
        next unless definition
        next unless supported_modifier?(definition, clause.modifier)

        scope = apply_clause(scope, definition, clause)
      end

      total = scope.count
      count = clamped_count
      offset = clamped_offset
      records = ordered(scope).limit(count).offset(offset)

      Result.new(records: records, total: total, count: count, offset: offset)
    end

    # Names of clauses this searcher cannot honor (unknown parameter or
    # unsupported modifier). Plain search silently skips them (lenient, per
    # spec); conditional interactions (Fhir::ConditionalMatch) reject instead,
    # since a skipped clause would broaden the criteria and select unintended
    # resources.
    def unsupported_clause_names
      search_params.clauses.reject do |clause|
        definition = definition_for(clause.name)
        definition && supported_modifier?(definition, clause.modifier)
      end.map(&:name)
    end

    private

    attr_reader :resource_type, :model, :search_param_defs, :search_params

    SORTABLE_META = { "_id" => :id, "_lastUpdated" => :last_updated }.freeze

    def definitions
      @definitions ||= SYSTEM_PARAMS.merge(search_param_defs)
    end

    def alias_index
      @alias_index ||= search_param_defs.each_with_object({}) do |(canonical, definition), idx|
        Array(definition[:aliases]).each { |a| idx[a] = canonical }
      end
    end

    def definition_for(name)
      return definitions[name] if definitions.key?(name)

      canonical = alias_index[name]
      canonical && definitions[canonical]
    end

    def supported_modifier?(definition, modifier)
      return true if modifier.nil?

      %i[string token_or_text].include?(definition[:type]) && STRING_MODIFIERS.include?(modifier)
    end

    def apply_clause(scope, definition, clause)
      case definition[:type]
      when :string then string_fragment(scope, definition[:column], clause, word_boundary: definition[:word_boundary])
      when :token then token_fragment(scope, definition[:column], clause)
      when :boolean then boolean_fragment(scope, definition[:column], clause)
      when :date, :datetime then date_fragment(scope, definition, clause)
      when :reference then reference_fragment(scope, definition, clause)
      when :identifier then identifier_fragment(scope, clause)
      when :token_or_text then token_or_text_fragment(scope, definition, clause)
      else raise ArgumentError, "Unknown search param type: #{definition[:type]}"
      end
    end

    # --- :string -----------------------------------------------------------

    def string_fragment(scope, column, clause, word_boundary: false)
      mode = string_mode(clause.modifier)
      where_or(scope, clause.values.map { |v| string_value_fragment(column, v, mode, word_boundary) })
    end

    def string_mode(modifier)
      case modifier
      when "exact" then :exact
      when "contains" then :contains
      else :starts_with
      end
    end

    # word_boundary columns (space-joined multi-token extractions like Patient#given
    # or Patient#name_text) additionally match mid-string at a token boundary, since a
    # plain prefix match would miss anything but the first token.
    def string_value_fragment(column, value, mode, word_boundary)
      case mode
      when :exact
        return ["#{column} = ?", [value]] unless word_boundary

        ["(#{column} = ? OR #{column} LIKE ? OR #{column} LIKE ? OR #{column} LIKE ?)",
         [value, "#{like_escape(value)} %", "% #{like_escape(value)}", "% #{like_escape(value)} %"]]
      when :contains
        ["#{column} ILIKE ?", ["%#{like_escape(value)}%"]]
      else
        return ["#{column} ILIKE ?", ["#{like_escape(value)}%"]] unless word_boundary

        ["(#{column} ILIKE ? OR #{column} ILIKE ?)", ["#{like_escape(value)}%", "% #{like_escape(value)}%"]]
      end
    end

    def like_escape(str)
      str.gsub(/[%_\\]/) { |c| "\\#{c}" }
    end

    # --- :token / :token_or_text --------------------------------------------

    # Token columns only ever store the code (not the system), so the system portion
    # of a `system|code` value is accepted but ignored -- every JP Core token param
    # implemented so far has a single fixed CodeSystem binding.
    def token_fragment(scope, column, clause)
      codes = clause.values.map { |v| token_code(v) }
      return scope if codes.empty?

      scope.where(column => codes)
    end

    def token_code(value)
      value.include?("|") ? value.split("|", 2).last : value
    end

    def token_or_text_fragment(scope, definition, clause)
      mode = string_mode(clause.modifier)
      fragments = clause.values.map do |v|
        text_sql, text_binds = string_value_fragment(definition[:text_column], v, mode, false)
        ["(#{definition[:token_column]} = ? OR #{text_sql})", [token_code(v), *text_binds]]
      end
      where_or(scope, fragments)
    end

    # --- :identifier ---------------------------------------------------------

    def identifier_fragment(scope, clause)
      fragments = clause.values.map { |v| identifier_value_fragment(v) }
      return scope if fragments.empty?

      sql = fragments.map(&:first).join(" OR ")
      binds = fragments.flat_map(&:last)
      ids = ResourceIdentifier.where(resource_type: resource_type).where(sql, *binds).select(:resource_id)
      scope.where(id: ids)
    end

    def identifier_value_fragment(value)
      return ["value = ?", [value]] unless value.include?("|")

      system, val = value.split("|", 2)
      return ["(system IS NULL AND value = ?)", [val]] if system.empty?

      ["(system = ? AND value = ?)", [system, val]]
    end

    # --- :boolean --------------------------------------------------------------

    def boolean_fragment(scope, column, clause)
      values = clause.values.map { |v| ActiveModel::Type::Boolean.new.cast(v) }
      scope.where(column => values)
    end

    # --- :reference --------------------------------------------------------------

    def reference_fragment(scope, definition, clause)
      refs = clause.values.map { |v| qualify_reference(v, definition[:target_type]) }
      return scope if refs.empty?

      unless definition[:multiple]
        return scope.where(definition[:column] => refs)
      end

      # 0..* reference lives only in content; match array membership via jsonb
      # containment (GIN-indexed), mirroring Fhir::IncludeResolver#query_reverse.
      fragments = refs.map do |ref|
        containment = { definition[:jsonb_key] => [nest(definition[:ref_path], ref)] }
        ["content @> ?", [containment.to_json]]
      end
      where_or(scope, fragments)
    end

    def qualify_reference(value, target_type)
      value.include?("/") ? value : "#{target_type}/#{value}"
    end

    # Builds the nested hash a jsonb containment query expects, e.g.
    # nest(["individual", "reference"], "Practitioner/1") => {"individual"=>{"reference"=>"Practitioner/1"}}
    def nest(path, value)
      path.reverse.reduce(value) { |acc, key| { key => acc } }
    end

    # --- :date / :datetime -------------------------------------------------------

    def date_fragment(scope, definition, clause)
      fragments = clause.values.filter_map { |v| date_value_fragment(definition, v) }
      where_or(scope, fragments)
    end

    def date_value_fragment(definition, value)
      prefix, date_str = split_date_prefix(value)
      return nil unless SUPPORTED_DATE_PREFIXES.include?(prefix)

      interval = parse_date_interval(date_str)
      return nil unless interval

      if definition[:end_column]
        period_fragment(prefix, interval, definition[:column], definition[:end_column])
      else
        point_fragment(prefix, interval, definition[:column])
      end
    end

    def split_date_prefix(value)
      match = value.match(DATE_PREFIX_PATTERN)
      match ? [match[1], match[2]] : ["eq", value]
    end

    # Expands a FHIR date/dateTime value to the half-open interval [lo, hi) implied by
    # its precision, e.g. "2024" => [2024-01-01, 2025-01-01). lo/hi may be Date or Time;
    # ActiveRecord/pg compare either correctly against both `date` and `timestamp`
    # columns, so callers don't need to normalize further.
    def parse_date_interval(str)
      case str
      when /\A\d{4}\z/
        lo = Date.new(str.to_i, 1, 1)
        [lo, lo.next_year]
      when /\A\d{4}-\d{2}\z/
        year, month = str.split("-").map(&:to_i)
        lo = Date.new(year, month, 1)
        [lo, lo.next_month]
      when /\A\d{4}-\d{2}-\d{2}\z/
        lo = Date.iso8601(str)
        [lo, lo.next_day]
      else
        lo = Time.iso8601(str)
        [lo, lo + 1]
      end
    rescue ArgumentError, TypeError
      nil
    end

    def point_fragment(prefix, interval, column)
      lo, hi = interval
      case prefix
      when "eq" then ["#{column} >= ? AND #{column} < ?", [lo, hi]]
      when "ne" then ["(#{column} < ? OR #{column} >= ?)", [lo, hi]]
      when "ge" then ["#{column} >= ?", [lo]]
      when "gt" then ["#{column} >= ?", [hi]]
      when "le" then ["#{column} < ?", [hi]]
      when "lt" then ["#{column} < ?", [lo]]
      end
    end

    # Encounter.date: matches against [period.start, period.end), where a NULL end
    # means "still ongoing" (open interval) and a NULL start means unbounded in the
    # past. `eq` is spec-correct containment (the search interval must fully contain
    # the period), not overlap -- a client wanting overlap combines ge/le.
    def period_fragment(prefix, interval, start_column, end_column)
      lo, hi = interval
      case prefix
      when "eq"
        ["#{start_column} IS NOT NULL AND #{start_column} >= ? AND #{end_column} IS NOT NULL AND #{end_column} < ?", [lo, hi]]
      when "ne"
        ["(#{start_column} IS NULL OR #{start_column} < ? OR #{end_column} IS NULL OR #{end_column} >= ?)", [lo, hi]]
      when "ge"
        ["(#{end_column} IS NULL OR #{end_column} >= ?)", [lo]]
      when "gt"
        ["(#{end_column} IS NULL OR #{end_column} >= ?)", [hi]]
      when "le"
        ["(#{start_column} IS NULL OR #{start_column} < ?)", [hi]]
      when "lt"
        ["(#{start_column} IS NULL OR #{start_column} < ?)", [lo]]
      end
    end

    # --- shared -----------------------------------------------------------------

    # ANDs one clause onto the scope, OR-joining its per-value SQL fragments. Skips
    # (leaves scope unchanged) when every value in the clause failed to produce a
    # fragment (e.g. all values were unparseable dates) -- same lenient behavior as
    # an unrecognized parameter.
    def where_or(scope, fragments)
      return scope if fragments.empty?

      sql = fragments.map(&:first).join(" OR ")
      binds = fragments.flat_map(&:last)
      scope.where(sql, *binds)
    end

    # --- sort / paging ------------------------------------------------------------

    def ordered(scope)
      clauses = sort_clauses
      return scope.order(:id) if clauses.empty?

      # Append id as a stable tiebreaker so pagination is deterministic.
      clauses[:id] ||= :asc
      scope.order(clauses)
    end

    def sort_clauses
      raw = search_params.sort
      return {} if raw.blank?

      raw.to_s.split(",").each_with_object({}) do |token, clauses|
        token = token.strip
        next if token.blank?

        descending = token.start_with?("-")
        name = descending ? token[1..] : token
        column = sort_column(name)
        next unless column

        clauses[column] ||= descending ? :desc : :asc
      end
    end

    def sort_column(name)
      return SORTABLE_META[name] if SORTABLE_META.key?(name)

      definition = search_param_defs[name]
      definition && definition[:column]&.to_sym
    end

    def clamped_count
      raw = search_params.count
      count = raw.present? ? raw.to_i : DEFAULT_COUNT
      count = DEFAULT_COUNT if count <= 0
      [count, MAX_COUNT].min
    end

    def clamped_offset
      raw = search_params.offset
      offset = raw.present? ? raw.to_i : 0
      offset.negative? ? 0 : offset
    end
  end
end
