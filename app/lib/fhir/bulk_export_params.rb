module Fhir
  # Parses and validates the kick-off parameters of a Bulk Data $export
  # request (Bulk Data Access IG v2.0.0): `_type`, `_since`, `_outputFormat`.
  # GET requests carry them as a query string; POST kick-offs (per the IG)
  # carry a FHIR Parameters resource body -- both are normalized to the same
  # flat param hash before parsing.
  class BulkExportParams
    class InvalidParams < StandardError; end

    OUTPUT_FORMAT_ALIASES = %w[application/fhir+ndjson application/ndjson ndjson].freeze
    SUPPORTED_PARAMS = %w[_type _since _outputFormat].freeze

    attr_reader :types, :since, :output_format, :unsupported_params

    def self.parse(query_string: nil, parameters_body: nil, valid_types:)
      new(flatten(query_string, parameters_body), valid_types).parse
    end

    # Merges a GET query string and/or a POST Parameters resource body into a
    # single { "name" => "value" } hash. Parameters entries use valueString.
    def self.flatten(query_string, parameters_body)
      from_query = query_string.present? ? Rack::Utils.parse_query(query_string) : {}
      from_body = Array(parameters_body&.dig("parameter")).each_with_object({}) do |param, hash|
        next unless param.is_a?(Hash) && param["name"]

        hash[param["name"]] = param.values_at("valueString", "valueInstant", "valueCode").compact.first
      end
      from_query.merge(from_body)
    end

    def initialize(raw_params, valid_types)
      @raw_params = raw_params
      @valid_types = valid_types
    end

    def parse
      @types = parse_types
      @since = parse_since
      @output_format = parse_output_format
      @unsupported_params = raw_params.keys - SUPPORTED_PARAMS
      self
    end

    private

    attr_reader :raw_params, :valid_types

    def parse_types
      raw = raw_params["_type"]
      return nil if raw.blank?

      requested = raw.split(",").map(&:strip).reject(&:blank?)
      unknown = requested - valid_types
      raise InvalidParams, "Unsupported _type value(s): #{unknown.join(', ')}" if unknown.any?

      requested
    end

    def parse_since
      raw = raw_params["_since"]
      return nil if raw.blank?

      Time.iso8601(raw)
    rescue ArgumentError
      raise InvalidParams, "Invalid _since value #{raw.inspect}: must be an ISO 8601 instant"
    end

    def parse_output_format
      raw = raw_params["_outputFormat"]
      return OUTPUT_FORMAT_ALIASES.first if raw.blank?

      unless OUTPUT_FORMAT_ALIASES.include?(raw)
        raise InvalidParams, "Unsupported _outputFormat #{raw.inspect}: only NDJSON is supported"
      end

      raw
    end
  end
end
