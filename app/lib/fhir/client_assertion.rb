module Fhir
  # Verifies a SMART Backend Services client assertion (private_key_jwt):
  # a JWT signed with the client's registered private key, presented at the
  # token endpoint instead of a shared secret.
  #
  # Enforced per the SMART spec:
  #   - alg RS384 or ES384, key selected from the client's registered JWKS
  #     (inline JWKS only; jwks_url fetching is a possible follow-up)
  #   - iss == sub == a registered client_id
  #   - aud == this token endpoint's URL
  #   - exp within 5 minutes of now (small clock skew allowed)
  #   - jti unused so far (replay protection via ClientAssertionJti)
  #
  # Implemented directly on OpenSSL rather than a JWT gem, keeping the app
  # dependency-free like the rest of the auth stack.
  class ClientAssertion
    JWT_BEARER_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer".freeze
    ALGORITHMS = %w[RS384 ES384].freeze
    MAX_LIFETIME = 5.minutes
    CLOCK_SKEW = 60.seconds

    Result = Struct.new(:client, :error_description, keyword_init: true) do
      def valid? = client.present?
    end

    def self.call(assertion, assertion_type:, audience:)
      new(assertion, assertion_type, audience).call
    end

    def initialize(assertion, assertion_type, audience)
      @assertion = assertion
      @assertion_type = assertion_type
      @audience = audience
    end

    def call
      return failure("client_assertion_type must be #{JWT_BEARER_TYPE}") unless @assertion_type == JWT_BEARER_TYPE

      header, claims, signing_input, signature = decode_jwt(@assertion)
      return failure("client_assertion is not a well-formed JWT") unless header

      return failure("Unsupported signing algorithm #{header['alg'].inspect} (expected RS384 or ES384)") unless ALGORITHMS.include?(header["alg"])

      client = OauthClient.find_by(id: claims["iss"])
      return failure("Unknown client or no registered JWKS") unless client&.jwks.present?
      return failure("iss and sub must both be the client_id") unless claims["sub"] == claims["iss"]
      return failure("aud must be the token endpoint URL #{@audience}") unless claims["aud"] == @audience

      exp_error = check_expiry(claims["exp"])
      return failure(exp_error) if exp_error

      return failure("jti is required") if claims["jti"].blank?

      key = signing_key(client.jwks, header)
      return failure("No usable key in the registered JWKS for kid #{header['kid'].inspect}") unless key
      return failure("Signature verification failed") unless verify_signature(key, header["alg"], signing_input, signature)

      # Register the jti only after full verification, so garbage requests
      # cannot poison the replay cache for a legitimate future assertion.
      unless ClientAssertionJti.register(client.id, claims["jti"], Time.zone.at(claims["exp"].to_i))
        return failure("Assertion replay detected (jti already used)")
      end

      Result.new(client: client)
    end

    private

    def failure(description)
      Result.new(error_description: description)
    end

    def decode_jwt(token)
      parts = token.to_s.split(".")
      return nil unless parts.length == 3

      header = JSON.parse(base64url_decode(parts[0]))
      claims = JSON.parse(base64url_decode(parts[1]))
      signature = base64url_decode(parts[2])
      return nil unless header.is_a?(Hash) && claims.is_a?(Hash)

      [header, claims, parts[0..1].join("."), signature]
    rescue ArgumentError, JSON::ParserError
      nil
    end

    def base64url_decode(str)
      padded = str + "=" * ((4 - str.length % 4) % 4)
      Base64.urlsafe_decode64(padded)
    end

    def check_expiry(exp)
      return "exp is required" unless exp.is_a?(Numeric) || exp.to_s.match?(/\A\d+\z/)

      expires_at = Time.zone.at(exp.to_i)
      now = Time.current
      return "Assertion has expired" if expires_at <= now - CLOCK_SKEW
      return "exp must be no more than 5 minutes in the future" if expires_at > now + MAX_LIFETIME + CLOCK_SKEW

      nil
    end

    # Selects the JWKS key matching the header's kid (or, absent a kid, the
    # first key usable with the algorithm) and converts it to an OpenSSL key.
    def signing_key(jwks, header)
      keys = Array(jwks["keys"]).select { |k| k.is_a?(Hash) }
      keys = keys.select { |k| k["kid"] == header["kid"] } if header["kid"].present?

      wanted_kty = header["alg"] == "RS384" ? "RSA" : "EC"
      jwk = keys.find { |k| k["kty"] == wanted_kty }
      return nil unless jwk

      jwk["kty"] == "RSA" ? rsa_key(jwk) : ec_key(jwk)
    rescue ArgumentError, OpenSSL::OpenSSLError
      nil
    end

    # RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER } --
    # built via ASN.1 because PKeys are immutable under OpenSSL 3.
    def rsa_key(jwk)
      modulus = OpenSSL::BN.new(base64url_decode(jwk.fetch("n")), 2)
      exponent = OpenSSL::BN.new(base64url_decode(jwk.fetch("e")), 2)
      der = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer(modulus), OpenSSL::ASN1::Integer(exponent)]).to_der
      OpenSSL::PKey::RSA.new(der)
    end

    # SubjectPublicKeyInfo for id-ecPublicKey/secp384r1 with the uncompressed
    # point 0x04 || x || y (ES384 keys are always P-384).
    def ec_key(jwk)
      return nil unless jwk["crv"] == "P-384"

      point = "\x04".b + base64url_decode(jwk.fetch("x")) + base64url_decode(jwk.fetch("y"))
      algorithm = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::ObjectId("id-ecPublicKey"), OpenSSL::ASN1::ObjectId("secp384r1")])
      der = OpenSSL::ASN1::Sequence([algorithm, OpenSSL::ASN1::BitString(point)]).to_der
      OpenSSL::PKey.read(der)
    end

    def verify_signature(key, alg, signing_input, signature)
      digest = OpenSSL::Digest::SHA384.new
      # A JWS ES384 signature is the raw 48-byte R and S concatenated; OpenSSL
      # verifies DER, so re-encode.
      signature = ecdsa_der(signature) if alg == "ES384"
      return false unless signature

      key.verify(digest, signature, signing_input)
    rescue OpenSSL::OpenSSLError
      false
    end

    def ecdsa_der(raw)
      return nil unless raw.bytesize == 96

      r = OpenSSL::BN.new(raw[0, 48], 2)
      s = OpenSSL::BN.new(raw[48, 48], 2)
      OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer(r), OpenSSL::ASN1::Integer(s)]).to_der
    end
  end
end
