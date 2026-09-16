module Fhir
  # Parsing shared by every endpoint that pages or filters by instant: search,
  # _history, $distinct-dates, AuditEvent, and $export.
  module QueryParam
    # Raised by .parse_instant; the message names the parameter (-> 400).
    class InvalidInstant < StandardError; end

    module_function

    # A page size: `default` when absent or non-positive, never above `max`.
    def clamp_count(raw, default:, max:)
      count = raw.present? ? raw.to_i : default
      count = default if count <= 0
      [count, max].min
    end

    def clamp_offset(raw)
      offset = raw.present? ? raw.to_i : 0
      offset.negative? ? 0 : offset
    end

    # An ISO 8601 instant, or nil when the parameter is absent.
    def parse_instant(raw, name:)
      return nil if raw.blank?

      Time.iso8601(raw)
    rescue ArgumentError, TypeError
      raise InvalidInstant, "Invalid #{name} value #{raw.inspect}: must be an ISO 8601 instant"
    end
  end
end
