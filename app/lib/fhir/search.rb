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

    DATE_PREFIX_PATTERN = /\A(eq|ne|ge|le|gt|lt|sa|eb|ap)(\d.*)\z/.freeze
    SUPPORTED_DATE_PREFIXES = %w[eq ne ge le gt lt sa eb ap].freeze

    STRING_MODIFIERS = %w[exact contains].freeze

    # :missing accepts exactly one value, true or false; anything else makes the
    # clause unsupported (rejected in conditional criteria, skipped in search).
    MISSING_VALUES = [%w[true], %w[false]].freeze

    # _id and _lastUpdated behave like any other search param (comma-OR, repeat-AND)
    # rather than being handled as special cases.
    # _id is a token matched against the primary key column (backing: :column), never
    # via resource_tokens -- it has no coding and no token rows.
    SYSTEM_PARAMS = {
      "_id" => { type: :token, column: :id, backing: :column },
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
      scope = filtered_scope
      total = compute_total(scope)
      count = clamped_count
      offset = clamped_offset
      records = count_only? ? [] : ordered(scope).limit(count).offset(offset)

      Result.new(records: records, total: total, count: count, offset: offset)
    end

    # The clause loop alone: every supported clause ANDed onto the base scope,
    # with no count/ordering/paging. Also the entry point for the INNER query of
    # a chained or _has clause, and for Fhir::ConditionalMatch.
    def filtered_scope
      scope = model.where(deleted: false)

      search_params.clauses.each do |clause|
        resolution = resolve_clause(clause)
        next unless resolution

        scope = apply_resolution(scope, resolution, clause)
      end

      scope
    end

    # Names of clauses this searcher cannot honor (unknown parameter or
    # unsupported modifier). Plain search silently skips them (lenient, per
    # spec); conditional interactions (Fhir::ConditionalMatch) reject instead,
    # since a skipped clause would broaden the criteria and select unintended
    # resources.
    def unsupported_clause_names
      search_params.clauses.reject { |clause| resolve_clause(clause) }.map(&:name)
    end

    # Public so _has resolution can look up the reference param (with aliases)
    # on the SOURCE type's searcher.
    def definition_for(name)
      return definitions[name] if definitions.key?(name)

      canonical = alias_index[name]
      canonical && definitions[canonical]
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

    # The canonical PARAMS key a clause resolves to (resource_tokens.param_name is keyed
    # by canonical name, so an alias like `patient` must map back to `subject`).
    def canonical_name(name)
      alias_index[name] || name
    end

    def supported_modifier?(definition, modifier)
      return true if modifier.nil?

      %i[string token_or_text].include?(definition[:type]) && STRING_MODIFIERS.include?(modifier)
    end

    # Single source of truth for whether (and how) a clause is honored, shared
    # by filtered_scope (lenient skip on nil) and unsupported_clause_names
    # (strict rejection on nil, via ConditionalMatch). Returns a tagged tuple:
    #   [:has, ref_definition, inner_search]
    #   [:chain, definition, inner_search]
    #   [:missing, definition]
    #   [:plain, definition]
    # or nil when the clause cannot be honored.
    def resolve_clause(clause)
      if (has = clause.has)
        return has_resolution(has, clause)
      end
      if (chain = clause.chain)
        return chain_resolution(chain, clause)
      end

      definition = definition_for(clause.name)
      return nil unless definition

      if clause.modifier == "missing"
        return MISSING_VALUES.include?(clause.values) ? [:missing, definition] : nil
      end

      supported_modifier?(definition, clause.modifier) ? [:plain, definition] : nil
    end

    def apply_resolution(scope, resolution, clause)
      kind, definition, inner = resolution
      case kind
      when :plain then apply_clause(scope, definition, clause)
      when :missing then missing_fragment(scope, definition, clause, clause.values == %w[true])
      when :chain then chain_fragment(scope, definition, inner)
      when :has then has_fragment(scope, definition, inner)
      end
    end

    # --- chained search / _has ------------------------------------------------

    # Single-level chains only: an inner param that would itself be a chain or a
    # _has makes the whole clause unsupported, so inner searches can never recurse.
    def chainable_tail?(param, tail_modifier)
      param != "_has" && !param.include?(".") && !tail_modifier.to_s.include?(".")
    end

    # subject:Patient.name=X / subject.name=X: valid iff the base is a reference
    # param whose (single) target type matches the explicit type when given, and
    # the target type fully supports the tail clause.
    def chain_resolution(chain, clause)
      definition = definition_for(chain.base)
      return nil unless definition && definition[:type] == :reference
      return nil if chain.target_type && chain.target_type != definition[:target_type]
      return nil unless chainable_tail?(chain.param, chain.tail_modifier)
      return nil unless ResourceRegistry.entry_for(definition[:target_type])

      inner = inner_search(definition[:target_type], chain.param, chain.tail_modifier, clause.values)
      inner.unsupported_clause_names.empty? ? [:chain, definition, inner] : nil
    end

    # _has:Observation:patient:code=X: valid iff the source type is registered,
    # its ref param is a reference back to THIS type, and the source type fully
    # supports the tail clause.
    def has_resolution(has, clause)
      return nil unless ResourceRegistry.entry_for(has.source_type)
      return nil unless chainable_tail?(has.param, has.tail_modifier)

      inner = inner_search(has.source_type, has.param, has.tail_modifier, clause.values)
      ref_definition = inner.definition_for(has.ref_param)
      return nil unless ref_definition && ref_definition[:type] == :reference
      return nil unless ref_definition[:target_type] == resource_type
      return nil unless inner.unsupported_clause_names.empty?

      [:has, ref_definition, inner]
    end

    # The inner query holds exactly one clause -- the chain/_has tail. Comma
    # values OR inside it; repeated outer clauses AND as usual.
    def inner_search(type, param, tail_modifier, values)
      Search.new(type, SearchParams.new([
        SearchParams::Clause.new(name: param, modifier: tail_modifier, values: values)
      ]))
    end

    def chain_fragment(scope, definition, inner)
      target_type = definition[:target_type]
      inner_scope = inner.filtered_scope

      unless definition[:multiple]
        # Pure SQL: column IN (SELECT 'Patient/' || id FROM ...). target_type
        # comes from the registry, never from client input.
        return scope.where(definition[:column] => inner_scope.select(Arel.sql("'#{target_type}/' || id")))
      end

      # 0..* references live in jsonb, so containment needs concrete ref strings.
      # An empty inner result must yield zero matches, not a lenient skip.
      refs = inner_scope.pluck(:id).map { |id| "#{target_type}/#{id}" }
      return scope.none if refs.empty?

      where_or(scope, refs.map do |ref|
        ["content @> ?", [{ definition[:jsonb_key] => [nest(definition[:ref_path], ref)] }.to_json]]
      end)
    end

    def has_fragment(scope, ref_definition, inner)
      inner_scope = inner.filtered_scope

      unless ref_definition[:multiple]
        # Concatenating on the OUTER side ('Patient/' || id) means a source row
        # referencing some other type simply never matches -- no prefix parsing.
        return scope.where(
          "'#{resource_type}/' || #{model.table_name}.id IN (#{inner_scope.select(ref_definition[:column]).to_sql})"
        )
      end

      # Multi-valued source references (only Encounter.location/participant):
      # extract refs in Ruby, mirroring IncludeResolver#collect_forward_refs.
      prefix = "#{resource_type}/"
      ids = inner_scope.pluck(:content).flat_map do |content|
        Array(content[ref_definition[:jsonb_key]]).filter_map do |element|
          element.dig(*ref_definition[:ref_path]) if element.is_a?(Hash)
        end
      end.filter_map { |ref| ref.delete_prefix(prefix) if ref.is_a?(String) && ref.start_with?(prefix) }

      scope.where(id: ids.uniq)
    end

    # --- :missing -------------------------------------------------------------

    def missing_fragment(scope, definition, clause, missing)
      case definition[:type]
      when :identifier
        ids = ResourceIdentifier.where(resource_type: resource_type).select(:resource_id)
        missing ? scope.where.not(id: ids) : scope.where(id: ids)
      when :token
        token_missing_fragment(scope, definition, clause, missing)
      when :token_or_text
        token_or_text_missing_fragment(scope, definition, clause, missing)
      when :date, :datetime
        if definition[:end_column]
          both_columns_missing(scope, definition[:column], definition[:end_column], missing)
        else
          null_fragment(scope, definition[:column], missing)
        end
      when :reference
        if definition[:multiple]
          # jsonb_exists() instead of the `?` operator, whose literal form would
          # collide with bind placeholders. A present-but-empty array counts as
          # not missing; the extractor never writes empty arrays.
          missing ? scope.where("NOT jsonb_exists(content, ?)", definition[:jsonb_key]) : scope.where("jsonb_exists(content, ?)", definition[:jsonb_key])
        else
          null_fragment(scope, definition[:column], missing)
        end
      else
        null_fragment(scope, definition[:column], missing)
      end
    end

    def null_fragment(scope, column, missing)
      scope.where("#{column} IS #{missing ? '' : 'NOT '}NULL")
    end

    def both_columns_missing(scope, first, second, missing)
      if missing
        scope.where("#{first} IS NULL AND #{second} IS NULL")
      else
        scope.where("#{first} IS NOT NULL OR #{second} IS NOT NULL")
      end
    end

    # present == has at least one resource_tokens row for this param (_id excepted:
    # it is column-backed, so its presence is the PK's nullability).
    def token_missing_fragment(scope, definition, clause, missing)
      return null_fragment(scope, definition[:column], missing) if definition[:backing] == :column

      ids = token_param_ids(clause)
      missing ? scope.where.not(id: ids) : scope.where(id: ids)
    end

    # token_or_text is missing only when BOTH the token rows and the text column are
    # absent; present when either exists. Built with Arel rather than interpolated
    # SQL so the table/column identifiers are never spliced into a raw string.
    def token_or_text_missing_fragment(scope, definition, clause, missing)
      table = model.arel_table
      text_col = table[definition[:text_column]]

      if missing
        scope.where.not(id: token_param_ids(clause)).where(text_col.eq(nil))
      else
        scope.where(table[:id].in(token_param_ids(clause).arel).or(text_col.not_eq(nil)))
      end
    end

    def token_param_ids(clause)
      ResourceToken.where(resource_type: resource_type, param_name: canonical_name(clause.name)).select(:resource_id)
    end

    def apply_clause(scope, definition, clause)
      case definition[:type]
      when :string then string_fragment(scope, definition[:column], clause, word_boundary: definition[:word_boundary])
      when :token then token_fragment(scope, definition, clause)
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

    # Token search matches (system, code) rows in resource_tokens (one row per coding,
    # all codings), so `system|code` is honored and multi-coded elements are found by
    # any of their codings. _id is the sole exception (backing: :column): it matches the
    # primary-key column directly. The flat token columns (status, class_code, ...) are
    # still populated for _sort but no longer used for matching.
    def token_fragment(scope, definition, clause)
      return column_token_fragment(scope, definition[:column], clause) if definition[:backing] == :column

      token_ids = token_id_scope(canonical_name(clause.name), clause.values)
      token_ids ? scope.where(id: token_ids) : scope
    end

    def column_token_fragment(scope, column, clause)
      codes = clause.values.map { |v| token_code(v) }
      return scope if codes.empty?

      scope.where(column => codes)
    end

    def token_code(value)
      value.include?("|") ? value.split("|", 2).last : value
    end

    # A resource_tokens subquery selecting the resource_ids whose (system, code) rows
    # satisfy any of the clause values, or nil when there are no values to match.
    def token_id_scope(param_name, values)
      fragments = values.map { |v| token_value_fragment(v) }
      return nil if fragments.empty?

      sql = fragments.map(&:first).join(" OR ")
      binds = fragments.flat_map(&:last)
      ResourceToken.where(resource_type: resource_type, param_name: param_name).where(sql, *binds).select(:resource_id)
    end

    # The four FHIR token forms: `code` (any system), `system|code`, `system|` (any
    # code in the system), `|code` (code with no system).
    def token_value_fragment(value)
      return ["code = ?", [value]] unless value.include?("|")

      system, code = value.split("|", 2)
      if system.empty?
        ["(system IS NULL AND code = ?)", [code]]
      elsif code.empty?
        ["system = ?", [system]]
      else
        ["(system = ? AND code = ?)", [system, code]]
      end
    end

    # token side (resource_tokens membership) OR text side (text_column ILIKE). The
    # token subquery is embedded via to_sql so it can be OR-combined with the text
    # fragments, mirroring has_fragment.
    def token_or_text_fragment(scope, definition, clause)
      mode = string_mode(clause.modifier)
      token_ids = token_id_scope(canonical_name(clause.name), clause.values)

      fragments = []
      fragments << ["#{model.table_name}.id IN (#{token_ids.to_sql})", []] if token_ids
      clause.values.each do |v|
        fragments << string_value_fragment(definition[:text_column], v, mode, false)
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

    # sa/eb ask whether the value lies entirely after/before the search interval;
    # for an instant column that collapses to gt/lt of the interval bounds.
    def point_fragment(prefix, interval, column)
      lo, hi = interval
      case prefix
      when "eq" then ["#{column} >= ? AND #{column} < ?", [lo, hi]]
      when "ne" then ["(#{column} < ? OR #{column} >= ?)", [lo, hi]]
      when "ge" then ["#{column} >= ?", [lo]]
      when "gt", "sa" then ["#{column} >= ?", [hi]]
      when "le" then ["#{column} < ?", [hi]]
      when "lt", "eb" then ["#{column} < ?", [lo]]
      when "ap"
        ap_lo, ap_hi = approx_interval(interval)
        ["#{column} >= ? AND #{column} < ?", [ap_lo, ap_hi]]
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
      when "sa"
        # The period must start after the search interval ends; a NULL start
        # (unbounded past) can never be entirely after.
        ["#{start_column} IS NOT NULL AND #{start_column} >= ?", [hi]]
      when "eb"
        # The period must end before the search interval starts; a NULL end
        # (still ongoing) can never be entirely before.
        ["#{end_column} IS NOT NULL AND #{end_column} < ?", [lo]]
      when "ap"
        # Overlap with the widened interval (contrast with eq's containment).
        ap_lo, ap_hi = approx_interval(interval)
        ["(#{start_column} IS NULL OR #{start_column} < ?) AND (#{end_column} IS NULL OR #{end_column} >= ?)", [ap_hi, ap_lo]]
      end
    end

    # ap widens the value's implicit interval by ±10% of the distance between
    # now and the interval midpoint (the de-facto interpretation, per the spec's
    # own suggestion and HAPI's default): recent dates get a tight tolerance,
    # historic ones proportionally wider. Alternative (a fixed widening) was
    # rejected as arbitrary across time scales. Callers pin `now` in tests via
    # travel_to.
    def approx_interval(interval, now: Time.current)
      lo = interval.first.to_time
      hi = interval.last.to_time
      delta = (now - (lo + (hi - lo) / 2)).abs * 0.1
      [lo - delta, hi + delta]
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

    # _summary=count returns totals only, so record fetching is skipped but the
    # COUNT always runs -- even under _total=none, which would otherwise leave
    # the response empty of information.
    def count_only?
      search_params.summary == "count"
    end

    # _total=none skips the COUNT query (total becomes nil and Bundle.total is
    # omitted); _total=estimate is answered with the accurate count, which the
    # spec explicitly allows.
    def compute_total(scope)
      return scope.count if count_only?
      return nil if search_params.total_mode == "none"

      scope.count
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
