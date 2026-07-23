module Fhir
  module Profile
    # FHIR R4 primitive datatype format checks (the regexes published in the
    # spec's data-types.html). Types not listed here -- complex datatypes,
    # BackboneElement, the internal "http://hl7.org/fhirpath/System.String"
    # marker FHIR snapshots use for `.id` elements, xhtml -- are intentionally
    # unchecked: #valid? returns nil so the caller skips the check rather than
    # guessing at a format we don't actually know.
    module Primitives
      REGEXES = {
        "integer" => /\A[0]|[-+]?[1-9][0-9]*\z/,
        "unsignedInt" => /\A(0|[1-9][0-9]*)\z/,
        "positiveInt" => /\A[1-9][0-9]*\z/,
        "string" => /\A[ \r\n\t\S]+\z/,
        "markdown" => /\A[ \r\n\t\S]+\z/,
        "code" => /\A[^\s]+( [^\s]+)*\z/,
        "id" => /\A[A-Za-z0-9\-.]{1,64}\z/,
        "uri" => /\A\S*\z/,
        "url" => /\A\S*\z/,
        "canonical" => /\A\S*\z/,
        "oid" => %r{\Aurn:oid:[0-2](\.(0|[1-9][0-9]*))+\z},
        "uuid" => /\Aurn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/,
        "base64Binary" => %r{\A(\s*([0-9a-zA-Z+/=]){4}\s*)*\z},
        "instant" => /\A([0-9]([0-9]([0-9][1-9]|[1-9]0)|[1-9]00)|[1-9]000)-(0[1-9]|1[0-2])-(0[1-9]|[1-2][0-9]|3[0-1])
                       T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?(Z|(\+|-)((0[0-9]|1[0-3]):[0-5][0-9]|14:00))\z/x,
        "date" => /\A([0-9]([0-9]([0-9][1-9]|[1-9]0)|[1-9]00)|[1-9]000)
                    (-(0[1-9]|1[0-2])(-(0[0-9]|[1-2][0-9]|3[0-1]))?)?\z/x,
        "dateTime" => /\A([0-9]([0-9]([0-9][1-9]|[1-9]0)|[1-9]00)|[1-9]000)
                        (-(0[1-9]|1[0-2])(-(0[0-9]|[1-2][0-9]|3[0-1])
                        (T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?
                        (Z|(\+|-)((0[0-9]|1[0-3]):[0-5][0-9]|14:00)))?)?)?\z/x,
        "time" => /\A([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?\z/
      }.freeze

      JSON_TYPE_CHECKS = {
        "boolean" => ->(v) { v == true || v == false },
        "integer" => ->(v) { v.is_a?(Integer) },
        "unsignedInt" => ->(v) { v.is_a?(Integer) },
        "positiveInt" => ->(v) { v.is_a?(Integer) },
        "decimal" => ->(v) { v.is_a?(Numeric) }
      }.freeze

      module_function

      def known?(type_code)
        REGEXES.key?(type_code) || JSON_TYPE_CHECKS.key?(type_code)
      end

      # true/false when the type is understood and checkable; nil when the
      # type code isn't one this module knows how to check (caller skips).
      def valid?(type_code, value)
        json_check = JSON_TYPE_CHECKS[type_code]
        return json_check.call(value) if json_check

        regex = REGEXES[type_code]
        return nil unless regex

        value.is_a?(String) && regex.match?(value)
      end
    end
  end
end
