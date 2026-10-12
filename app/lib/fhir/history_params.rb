module Fhir
  # Parses the query parameters of a type-/system-level history request
  # (`_count`, `_offset`, `_since`). SearchParams is not reused here because it
  # would treat `_since` as an ordinary search clause, and the count/offset
  # clamping in Fhir::Search is private to searching.
  #
  # Everything else in the query string is kept verbatim as `criteria`: a
  # type-level history narrowed by search parameters (FhirResourcesController#
  # type_history) hands it to Fhir::Search, and the paging links carry it along.
  class HistoryParams
    # Raised for a `_since` value that is not a parseable instant (-> 400).
    InvalidSince = QueryParam::InvalidInstant

    DEFAULT_COUNT = Search::DEFAULT_COUNT
    MAX_COUNT = Search::MAX_COUNT

    OWN_NAMES = %w[_count _offset _since _format].freeze

    attr_reader :count, :offset, :since, :criteria

    def self.parse(query_string)
      new(Rack::Utils.parse_query(query_string.to_s), criteria: criteria_of(query_string))
    end

    # The query string minus this class's own parameters, pairs kept as sent
    # (repeats and comma lists are SearchParams' to interpret).
    def self.criteria_of(query_string)
      query_string.to_s.sub(/\A\?/, "").split("&").reject do |pair|
        key = pair.partition("=").first
        key.empty? || OWN_NAMES.include?(Rack::Utils.unescape(key))
      end.join("&")
    end
    private_class_method :criteria_of

    def initialize(params, criteria: "")
      @count = clamp_count(params["_count"])
      @offset = clamp_offset(params["_offset"])
      @since = parse_since(params["_since"])
      @criteria = criteria
    end

    def criteria?
      criteria.present?
    end

    # Query string for pagination links; `_offset` last, mirroring
    # SearchParams#to_query.
    def to_query(offset:)
      parts = []
      parts << criteria if criteria?
      parts << "_since=#{Rack::Utils.escape(since.utc.iso8601(3))}" if since
      parts << "_count=#{count}"
      parts << "_offset=#{offset}"
      parts.join("&")
    end

    private

    def clamp_count(raw)
      QueryParam.clamp_count(raw, default: DEFAULT_COUNT, max: MAX_COUNT)
    end

    def clamp_offset(raw)
      QueryParam.clamp_offset(raw)
    end

    # A repeated `_since` arrives as an Array from parse_query; take the last,
    # matching SearchParams' last-value-wins behavior for meta params.
    def parse_since(raw)
      QueryParam.parse_instant(raw.is_a?(Array) ? raw.last : raw, name: "_since")
    end
  end
end
