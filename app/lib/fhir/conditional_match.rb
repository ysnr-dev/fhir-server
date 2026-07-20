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
    Result = Struct.new(:outcome, :record, :diagnostics, keyword_init: true)

    # Returns a Result whose outcome is one of:
    #   :invalid  - criteria empty or contains unsupported parameters/modifiers
    #   :none     - no current (non-deleted) resource matches
    #   :one      - exactly one matches (record is set)
    #   :multiple - more than one matches
    def self.call(resource_type, criteria)
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

      result = searcher.call
      case result.total
      when 0 then Result.new(outcome: :none)
      when 1 then Result.new(outcome: :one, record: result.records.first)
      else
        Result.new(
          outcome: :multiple,
          diagnostics: "Multiple #{resource_type} resources (#{result.total}) match the conditional criteria"
        )
      end
    end
  end
end
