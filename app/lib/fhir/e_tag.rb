module Fhir
  # Parses the versionId out of an ETag-shaped value.
  #
  # A version precondition reaches us in two shapes: the `If-Match` HTTP header
  # on a plain PUT/PATCH, and `Bundle.entry.request.ifMatch` inside a
  # transaction. Both carry an ETag (`W/"2"`), so the unwrapping lives here
  # rather than at each call site -- a raw `to_i` on `W/"2"` yields 0 and would
  # silently fail every precondition.
  module ETag
    # Returns the version as an Integer, or nil when no precondition was given.
    # A malformed value (non-blank but carrying no version) returns 0, which
    # never matches a real versionId: a precondition we cannot understand must
    # fail the request, not pass unchecked.
    def self.version_id(value)
      return nil if value.blank?

      value.to_s[/\d+/].to_i
    end
  end
end
