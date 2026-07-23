require "set"

module Fhir
  module Profile
    # Walks a resource payload against a JP Core StructureDefinition snapshot
    # (via ElementTree) and reports conformance issues in the same
    # { code:, diagnostics:, expression: } shape the hand-written per-resource
    # validators use, so Fhir::OperationOutcome.build needs no changes.
    #
    # Checks performed: cardinality (min/max), array-vs-singleton shape,
    # unknown elements, primitive format, fixed[x]/pattern[x], required
    # bindings resolvable from vendored ValueSets/CodeSystems, slicing with
    # `value` discriminators on system/url, and one level of recursion into
    # vendored JP Core datatype/extension profiles referenced via
    # `type[].profile`. FHIRPath invariants and Reference target resolution
    # are out of scope (existing hand validators cover reference existence).
    #
    # Every issue is emitted as an error (Result#errors) -- Fhir::Profile.mode
    # decides at the call site (Fhir::Operation) whether that blocks a write
    # or only surfaces via $validate / logs.
    class Validator
      def self.call(payload, profile_url:)
        new(payload, profile_url).call
      end

      def initialize(payload, profile_url)
        @payload = payload
        @profile_url = profile_url
        @errors = []
        @visited_profiles = Set.new
      end

      def call
        definition = DefinitionStore.structure_definition(@profile_url)
        tree = definition && ElementTree.build(definition)
        validate_value(tree, @payload, tree.path) if tree

        ResourceValidator::Result.new(@errors, [])
      end

      private

      def add_error(code:, diagnostics:, expression:)
        @errors << { code: code, diagnostics: diagnostics, expression: Array(expression) }
      end

      # --- single-value dispatch --------------------------------------------

      def validate_value(node, value, expression)
        type_code = single_type_code(node)

        check_fixed_pattern(node, value, expression)
        check_binding(node, value, type_code, expression) if type_code

        if type_code && Primitives.known?(type_code)
          result = Primitives.valid?(type_code, value)
          if result == false
            add_error(code: "value", diagnostics: "#{expression} is not a valid #{type_code} (JP Core: #{@profile_url})",
                      expression: expression)
          end
        else
          recurse_into_profile(node, value, expression)
          walk_complex(node, value, expression) if node.children.any?
        end
      end

      def single_type_code(node)
        return nil if node.types.size != 1

        code = node.types.first["code"]
        return nil if code.nil? || code.start_with?("http://") # FHIRPath pseudo-types (element .id) -- unchecked

        code
      end

      # --- complex object walking -------------------------------------------

      def walk_complex(node, value, expression)
        unless value.is_a?(Hash)
          add_error(code: "structure", diagnostics: "#{expression} must be an object (JP Core: #{@profile_url})",
                    expression: expression)
          return
        end

        check_unknown_keys(node, value, expression)
        node.children.each_value { |child| validate_child(value, child, expression) }
      end

      def check_unknown_keys(node, value, expression)
        allowed = Set.new(["resourceType"])
        node.children.each_value do |child|
          expand_child_name(child).each do |key|
            allowed << key
            allowed << "_#{key}"
          end
        end

        value.each_key do |key|
          next if allowed.include?(key)

          add_error(code: "structure",
                    diagnostics: "Unknown element '#{key}' is not part of #{node.path} (JP Core: #{@profile_url})",
                    expression: "#{expression}.#{key}")
        end
      end

      def expand_child_name(child)
        return [child.name] unless child.name.end_with?("[x]")

        expand_choice_keys(child)
      end

      def expand_choice_keys(child)
        base = child.name.delete_suffix("[x]")
        child.types.filter_map do |type|
          suffix = capitalized_type(type["code"])
          suffix && base + suffix
        end
      end

      def capitalized_type(code)
        return nil if code.nil? || code.empty? || code.start_with?("http://")

        code[0].upcase + code[1..]
      end

      # --- one child element (may repeat / be sliced) ------------------------

      def validate_child(value, child, expression_base)
        is_array = child.base_max == "*"
        key, raw = resolve_raw(child, value, expression_base)

        if !raw.nil? && is_array != raw.is_a?(Array)
          add_error(
            code: "structure",
            diagnostics: "#{expression_base}.#{key} must #{is_array ? '' : 'not '}be represented as a JSON array " \
                         "(JP Core: #{@profile_url})",
            expression: "#{expression_base}.#{key}"
          )
          return
        end

        occurrences = raw.nil? ? [] : (is_array ? raw : [raw])
        check_cardinality(child, occurrences.size, expression_base, key)
        return if occurrences.empty?

        if child.slicing && child.slices.any?
          validate_sliced_occurrences(child, occurrences, expression_base, key, is_array)
        else
          occurrences.each_with_index do |item, index|
            validate_value(child, item, occurrence_expression(expression_base, key, index, is_array))
          end
        end
      end

      def occurrence_expression(expression_base, key, index, is_array)
        is_array ? "#{expression_base}.#{key}[#{index}]" : "#{expression_base}.#{key}"
      end

      def resolve_raw(child, value, expression_base)
        return [child.name, value[child.name]] unless child.name.end_with?("[x]")

        keys = expand_choice_keys(child)
        present = keys.select { |k| value.key?(k) }
        if present.size > 1
          add_error(code: "invariant", diagnostics: "#{expression_base}.#{child.name}: only one of " \
                                                      "#{present.join(', ')} may be present",
                    expression: present.map { |k| "#{expression_base}.#{k}" })
        end

        key = present.first
        [key || child.name.delete_suffix("[x]"), key ? value[key] : nil]
      end

      def check_cardinality(child, count, expression_base, key)
        min = child.min.to_i
        if count < min
          add_error(
            code: "required",
            diagnostics: "#{expression_base}.#{key} is required (JP Core: #{child.min}..#{child.max || '*'})",
            expression: "#{expression_base}.#{key}"
          )
        end

        return if child.max.nil? || child.max == "*"

        max = child.max.to_i
        return unless count > max

        add_error(
          code: "structure",
          diagnostics: "#{expression_base}.#{key} allows at most #{child.max} occurrence(s) (JP Core)",
          expression: "#{expression_base}.#{key}"
        )
      end

      # --- slicing -------------------------------------------------------------

      def validate_sliced_occurrences(child, occurrences, expression_base, key, is_array)
        slice_counts = Hash.new(0)

        occurrences.each_with_index do |item, index|
          expr = occurrence_expression(expression_base, key, index, is_array)
          matched = child.slices.find { |slice| slice_matches?(slice, item) }

          if matched
            slice_counts[matched] += 1
            validate_value(matched, item, expr)
          else
            if child.slicing["rules"] == "closed"
              add_error(
                code: "structure",
                diagnostics: "#{expr} does not match any defined slice of #{child.path} (closed slicing, JP Core)",
                expression: expr
              )
            end
            validate_value(child, item, expr)
          end
        end

        check_slice_cardinalities(child, slice_counts, expression_base, key)
      end

      def slice_matches?(slice, item)
        return false unless slice.discriminator
        return false unless item.is_a?(Hash)

        # A discriminator path may cross a repeating element (e.g. JP_Observation_Common
        # slices Observation.category by "coding.system", and .coding is itself an
        # array) -- per FHIR slicing rules that's satisfied if ANY value the path
        # resolves to (fanning out over every array encountered along the way)
        # equals the expected value, not just the first one found.
        slice.discriminator.all? { |d| dig_values(item, d[:path]).include?(d[:value]) }
      end

      def dig_values(value, path)
        collect_values(value, path.to_s.split("."))
      end

      def collect_values(value, segments)
        return [value] if segments.empty?

        segment, *rest = segments
        case value
        when Hash
          collect_values(value[segment], rest)
        when Array
          value.flat_map { |item| collect_values(item, segments) }
        else
          []
        end
      end

      def check_slice_cardinalities(child, slice_counts, expression_base, key)
        child.slices.each do |slice|
          next unless slice.discriminator # unmatchable slice -- can't know how many items belong to it

          count = slice_counts[slice]
          min = slice.min.to_i
          if count < min
            add_error(
              code: "required",
              diagnostics: "#{expression_base}.#{key}:#{slice.slice_name} requires at least " \
                           "#{slice.min} occurrence(s) (JP Core)",
              expression: "#{expression_base}.#{key}"
            )
          end

          next if slice.max.nil? || slice.max == "*"

          max = slice.max.to_i
          next unless count > max

          add_error(
            code: "structure",
            diagnostics: "#{expression_base}.#{key}:#{slice.slice_name} allows at most " \
                         "#{slice.max} occurrence(s) (JP Core)",
            expression: "#{expression_base}.#{key}"
          )
        end
      end

      # --- fixed / pattern / binding -------------------------------------------

      def check_fixed_pattern(node, value, expression)
        if node.fixed
          unless PatternMatcher.fixed_match?(node.fixed[:value], value)
            add_error(
              code: "value",
              diagnostics: "#{expression} must be fixed to #{node.fixed[:value].inspect} (JP Core: #{@profile_url})",
              expression: expression
            )
          end
        elsif node.pattern
          unless PatternMatcher.pattern_match?(node.pattern[:value], value)
            add_error(
              code: "value",
              diagnostics: "#{expression} does not match the required pattern (JP Core: #{@profile_url})",
              expression: expression
            )
          end
        end
      end

      def check_binding(node, value, type_code, expression)
        binding = node.binding
        return unless binding && binding["strength"] == "required" && binding["valueSet"]

        codes = extract_codes(type_code, value)
        return if codes.nil? || codes.empty?

        expansion = DefinitionStore.expansion(binding["valueSet"])
        return if expansion.nil?
        return if codes.any? { |c| expansion.include?(c) }

        add_error(
          code: "value",
          diagnostics: "#{expression}: code(s) #{codes.join(', ')} not in required binding " \
                       "#{binding['valueSet']} (JP Core)",
          expression: expression
        )
      end

      def extract_codes(type_code, value)
        case type_code
        when "code"
          value.is_a?(String) ? [value] : nil
        when "Coding"
          return nil unless value.is_a?(Hash)

          value["code"] ? [value["code"]] : []
        when "CodeableConcept"
          return nil unless value.is_a?(Hash)

          Array(value["coding"]).filter_map { |c| c["code"] if c.is_a?(Hash) }
        when "Quantity"
          return nil unless value.is_a?(Hash)

          value["code"] ? [value["code"]] : []
        end
      end

      # --- nested JP Core datatype / extension profiles ------------------------

      def recurse_into_profile(node, value, expression)
        return unless node.types.size == 1

        profile_url = node.types.first["profile"]&.first&.split("|")&.first
        return unless Fhir::Profile.jp_core_profile?(profile_url)
        return if @visited_profiles.include?(profile_url)

        definition = DefinitionStore.structure_definition(profile_url)
        return unless definition

        tree = ElementTree.build(definition)
        return unless tree

        @visited_profiles << profile_url
        validate_value(tree, value, expression)
        @visited_profiles.delete(profile_url)
      end
    end
  end
end
