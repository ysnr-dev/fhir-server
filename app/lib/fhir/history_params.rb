module Fhir
  # Parses the query parameters of a type-/system-level history request
  # (`_count`, `_offset`, `_since`). SearchParams is not reused here because it
  # would treat `_since` as an ordinary search clause, and the count/offset
  # clamping in Fhir::Search is private to searching.
  class HistoryParams
    # Raised for a `_since` value that is not a parseable instant (-> 400).
    class InvalidSince < StandardError; end

    DEFAULT_COUNT = Search::DEFAULT_COUNT
    MAX_COUNT = Search::MAX_COUNT

    attr_reader :count, :offset, :since

    def self.parse(query_string)
      new(Rack::Utils.parse_query(query_string.to_s))
    end

    def initialize(params)
      @count = clamp_count(params["_count"])
      @offset = clamp_offset(params["_offset"])
      @since = parse_since(params["_since"])
    end

    # Query string for pagination links; `_offset` last, mirroring
    # SearchParams#to_query.
    def to_query(offset:)
      parts = []
      parts << "_since=#{Rack::Utils.escape(since.utc.iso8601(3))}" if since
      parts << "_count=#{count}"
      parts << "_offset=#{offset}"
      parts.join("&")
    end

    private

    def clamp_count(raw)
      count = raw.present? ? raw.to_i : DEFAULT_COUNT
      count = DEFAULT_COUNT if count <= 0
      [count, MAX_COUNT].min
    end

    def clamp_offset(raw)
      offset = raw.present? ? raw.to_i : 0
      offset.negative? ? 0 : offset
    end

    def parse_since(raw)
      # A repeated `_since` arrives as an Array from parse_query; take the last,
      # matching SearchParams' last-value-wins behavior for meta params.
      value = raw.is_a?(Array) ? raw.last : raw
      return nil if value.blank?

      Time.iso8601(value)
    rescue ArgumentError
      raise InvalidSince, "Invalid _since value #{value.inspect}: must be an ISO 8601 instant"
    end
  end
end
