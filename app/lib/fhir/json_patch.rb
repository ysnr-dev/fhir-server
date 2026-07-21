module Fhir
  # Applies a JSON Patch (RFC 6902) document to a Hash/Array structure without
  # mutating the input. Implemented in-repo (all six ops, RFC 6901 pointers)
  # rather than pulling in a gem, keeping the app's runtime dependencies to
  # Rails alone.
  #
  # Error split mirrors the HTTP mapping in Fhir::Operation#patch:
  #   InvalidPatch - the patch document itself is malformed (not an array,
  #                  unknown op, missing path/from/value, bad pointer syntax)
  #   ApplyFailure - the patch is well-formed but cannot be applied to THIS
  #                  document (missing target, index out of range, failed test)
  class JsonPatch
    class InvalidPatch < StandardError; end
    class ApplyFailure < StandardError; end

    OPS = %w[add remove replace move copy test].freeze
    # `value` presence is checked with key?/has-key semantics: JSON null is a
    # legal value for add/replace/test.
    OPS_REQUIRING_VALUE = %w[add replace test].freeze
    OPS_REQUIRING_FROM = %w[move copy].freeze

    def self.apply(document, operations)
      new(document, operations).apply
    end

    def initialize(document, operations)
      @document = document.deep_dup
      @operations = operations
    end

    def apply
      raise InvalidPatch, "Patch document must be a JSON array of operations" unless operations.is_a?(Array)
      raise InvalidPatch, "Patch document must not be empty" if operations.empty?

      operations.each_with_index do |operation, index|
        @document = apply_operation(validate_operation(operation, index), index)
      end

      document
    end

    private

    attr_reader :document, :operations

    def validate_operation(operation, index)
      raise InvalidPatch, "Operation #{index} must be a JSON object" unless operation.is_a?(Hash)

      op = operation["op"]
      raise InvalidPatch, "Operation #{index} has unknown op #{op.inspect}" unless OPS.include?(op)
      raise InvalidPatch, "Operation #{index} (#{op}) is missing 'path'" unless operation["path"].is_a?(String)

      if OPS_REQUIRING_VALUE.include?(op) && !operation.key?("value")
        raise InvalidPatch, "Operation #{index} (#{op}) is missing 'value'"
      end
      if OPS_REQUIRING_FROM.include?(op) && !operation["from"].is_a?(String)
        raise InvalidPatch, "Operation #{index} (#{op}) is missing 'from'"
      end

      operation
    end

    def apply_operation(operation, index)
      op = operation["op"]
      path = parse_pointer(operation["path"], index)

      case op
      when "add"
        add(document, path, operation["value"].deep_dup, index)
      when "remove"
        remove(document, path, index)
      when "replace"
        replace(document, path, operation["value"].deep_dup, index)
      when "move"
        from = parse_pointer(operation["from"], index)
        if from.length < path.length && path.first(from.length) == from
          raise ApplyFailure, "Operation #{index} (move): 'from' must not be a proper prefix of 'path'"
        end

        value = fetch(document, from, index)
        remove(document, from, index)
        add(document, path, value, index)
      when "copy"
        from = parse_pointer(operation["from"], index)
        add(document, path, fetch(document, from, index).deep_dup, index)
      when "test"
        actual = fetch(document, path, index)
        unless actual == operation["value"]
          raise ApplyFailure,
                "Operation #{index} (test) failed at #{operation['path'].inspect}: " \
                "expected #{operation['value'].to_json}, got #{actual.to_json}"
        end
        document
      end
    end

    # RFC 6901: "" is the whole document; each token unescapes ~1 -> "/" then
    # ~0 -> "~" (in that order, so "~01" round-trips to "~1").
    def parse_pointer(pointer, index)
      return [] if pointer == ""
      raise InvalidPatch, "Operation #{index} has invalid JSON Pointer #{pointer.inspect}" unless pointer.start_with?("/")

      pointer.split("/", -1)[1..].map { |token| token.gsub("~1", "/").gsub("~0", "~") }
    end

    # `add`/`remove`/`replace`/`move`/`copy` all return the (possibly new) root
    # document so a root-pointer target ("") can replace the whole thing.
    def add(doc, path, value, index)
      return value if path.empty?

      parent = fetch(doc, path[0..-2], index)
      token = path.last

      case parent
      when Hash
        parent[token] = value
      when Array
        if token == "-"
          parent << value
        else
          position = array_index(token, index)
          raise ApplyFailure, "Operation #{index}: array index #{token} out of range" if position > parent.length

          parent.insert(position, value)
        end
      else
        raise ApplyFailure, "Operation #{index}: cannot add a child to a #{parent.class} at #{pointer_string(path[0..-2])}"
      end

      doc
    end

    # Unlike remove+add, replace must be in-place so array neighbors keep their
    # positions; the target is required to exist (RFC 6902 section 4.3).
    def replace(doc, path, value, index)
      return value if path.empty?

      parent = fetch(doc, path[0..-2], index)
      token = path.last

      case parent
      when Hash
        raise ApplyFailure, "Operation #{index}: no member #{token.inspect} at #{pointer_string(path[0..-2])}" unless parent.key?(token)

        parent[token] = value
      when Array
        position = array_index(token, index)
        raise ApplyFailure, "Operation #{index}: array index #{token} out of range" if position >= parent.length

        parent[position] = value
      else
        raise ApplyFailure, "Operation #{index}: cannot replace a child of a #{parent.class} at #{pointer_string(path[0..-2])}"
      end

      doc
    end

    def remove(doc, path, index)
      raise ApplyFailure, "Operation #{index}: cannot remove the whole document" if path.empty?

      parent = fetch(doc, path[0..-2], index)
      token = path.last

      case parent
      when Hash
        raise ApplyFailure, "Operation #{index}: no member #{token.inspect} at #{pointer_string(path[0..-2])}" unless parent.key?(token)

        parent.delete(token)
      when Array
        position = array_index(token, index)
        raise ApplyFailure, "Operation #{index}: array index #{token} out of range" if position >= parent.length

        parent.delete_at(position)
      else
        raise ApplyFailure, "Operation #{index}: cannot remove from a #{parent.class} at #{pointer_string(path[0..-2])}"
      end

      doc
    end

    def fetch(doc, path, index)
      path.reduce(doc) do |current, token|
        case current
        when Hash
          raise ApplyFailure, "Operation #{index}: no member #{token.inspect} in document" unless current.key?(token)

          current[token]
        when Array
          position = array_index(token, index)
          raise ApplyFailure, "Operation #{index}: array index #{token} out of range" if position >= current.length

          current[position]
        else
          raise ApplyFailure, "Operation #{index}: cannot descend into a #{current.class}"
        end
      end
    end

    # Array references must be a non-negative integer without leading zeros
    # (RFC 6901); "-" is only legal for add and is handled by its caller.
    def array_index(token, index)
      raise ApplyFailure, "Operation #{index}: invalid array index #{token.inspect}" unless token.match?(/\A(0|[1-9]\d*)\z/)

      Integer(token, 10)
    end

    def pointer_string(path)
      "/#{path.map { |token| token.gsub('~', '~0').gsub('/', '~1') }.join('/')}"
    end
  end
end
