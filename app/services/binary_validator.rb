class BinaryValidator < ResourceValidator
  private

  def validate
    require_field("contentType")
    validate_data
  end

  # Binary.data is 0..1 base64Binary; reject undecodable payloads up front so
  # the raw-content read path never has to cope with garbage.
  def validate_data
    data = payload["data"]
    return if data.nil?

    unless data.is_a?(String) && base64?(data)
      add_error(code: "value", diagnostics: "Binary.data must be a base64-encoded string", expression: "Binary.data")
    end
  end

  def base64?(value)
    Base64.strict_decode64(value)
    true
  rescue ArgumentError
    false
  end
end
