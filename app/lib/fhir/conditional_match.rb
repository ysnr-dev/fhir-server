module Fhir
  # Resolves the search criteria of a conditional interaction (If-None-Exist,
  # conditional update, conditional reference) to zero, one, or many current
  # records of a resource type.
  #
  # Unlike plain search -- which is lenient and silently ignores unknown
  # parameters -- conditional criteria are strict: an empty or unrecognized
  # criteria set is rejected as :invalid rather than silently matching more
  # resources than the client intended.
  class ConditionalMatch
    Result = Struct.new(:outcome, :record, :records, :diagnostics, keyword_init: true)

    # Returns a Result whose outcome is one of:
    #   :invalid  - criteria empty or contains unsupported parameters/modifiers
    #   :none     - no current (non-deleted) resource matches
    #   :one      - exactly one matches (record is set)
    #   :multiple - more than one matches
    def self.call(resource_type, criteria)
      scope = strict_scope(resource_type, criteria)
      return scope if scope.is_a?(Result) # :invalid

      # Two records are enough to detect :multiple.
      records = scope.limit(2).to_a
      case records.length
      when 0 then Result.new(outcome: :none)
      when 1 then Result.new(outcome: :one, record: records.first)
      else
        Result.new(
          outcome: :multiple,
          diagnostics: "Multiple #{resource_type} resources match the conditional criteria"
        )
      end
    end

    # Every current record matching the criteria, for interactions that accept
    # multiple matches (conditional delete with conditionalDelete: "multiple").
    # Outcomes: :invalid, :none, or :multiple with `records` set (also for a
    # single match -- the caller treats one and many alike).
    def self.all(resource_type, criteria)
      scope = strict_scope(resource_type, criteria)
      return scope if scope.is_a?(Result) # :invalid

      records = scope.to_a
      return Result.new(outcome: :none, records: []) if records.empty?

      Result.new(outcome: :multiple, records: records)
    end

    # The strictly-validated match scope (ordered for determinism), or an
    # :invalid Result. Unlike plain search -- lenient -- conditional criteria
    # reject unknown parameters, since a skipped clause would broaden the
    # criteria and select unintended resources. filtered_scope (not #call) so
    # result-shaping meta params in the criteria (_summary=count, _total=none,
    # _count/_offset paging) can never distort the decision.
    def self.strict_scope(resource_type, criteria)
      search_params = SearchParams.parse(criteria.to_s)
      if search_params.clauses.empty?
        return Result.new(
          outcome: :invalid,
          diagnostics: "Conditional criteria must contain at least one search parameter"
        )
      end

      searcher = Search.new(resource_type, search_params)
      unsupported = searcher.unsupported_clause_names
      if unsupported.any?
        return Result.new(
          outcome: :invalid,
          diagnostics: "Unsupported search parameter(s) in conditional criteria: #{unsupported.join(', ')}"
        )
      end

      searcher.filtered_scope.order(:id)
    end
    private_class_method :strict_scope
  end
end
