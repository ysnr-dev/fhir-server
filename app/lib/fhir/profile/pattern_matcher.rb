module Fhir
  module Profile
    # Implements the two FHIR conformance-checking semantics for `fixed[x]`
    # and `pattern[x]` constraints against a parsed JSON payload value.
    module PatternMatcher
      module_function

      # fixed[x]: the value must be exactly the fixed value -- same keys, same
      # array length/order, recursively.
      def fixed_match?(fixed, value)
        case fixed
        when Hash
          value.is_a?(Hash) && fixed.keys.sort == value.keys.sort &&
            fixed.all? { |k, v| fixed_match?(v, value[k]) }
        when Array
          value.is_a?(Array) && fixed.size == value.size &&
            fixed.each_with_index.all? { |item, i| fixed_match?(item, value[i]) }
        else
          fixed == value
        end
      end

      # pattern[x]: the value must contain everything the pattern specifies,
      # but may have additional keys/array items. An array pattern matches
      # against the value array's items at the same index, in order (the
      # value array may be longer).
      def pattern_match?(pattern, value)
        case pattern
        when Hash
          value.is_a?(Hash) && pattern.all? { |k, v| value.key?(k) && pattern_match?(v, value[k]) }
        when Array
          value.is_a?(Array) && value.size >= pattern.size &&
            pattern.each_with_index.all? { |item, i| pattern_match?(item, value[i]) }
        else
          pattern == value
        end
      end
    end
  end
end
