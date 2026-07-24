module Fhir
  # The server's own RSA key for signing OpenID Connect id_tokens (RS384, to
  # match the ALGORITHMS this app already verifies for client assertions).
  #
  # In production the key MUST be stable across restarts and across every
  # instance, or an id_token signed by one process fails verification against
  # the jwks_uri served by another. Supply it as a PEM via OIDC_SIGNING_KEY.
  # When unset (development, test) an ephemeral key is generated once per
  # process -- fine locally, useless in a multi-instance deploy, hence the warn.
  #
  # Kept on OpenSSL directly, like Fhir::ClientAssertion, so the auth stack
  # stays dependency-free.
  module SigningKey
    ALG = "RS384".freeze
    mattr_accessor :cached_key

    class << self
      def private_key
        self.cached_key ||= load_or_generate
      end

      # RFC 7638 JWK thumbprint (SHA-256, base64url). Deterministic from the
      # public key, so the kid in the id_token header always matches the kid
      # published at jwks_uri without any separate bookkeeping.
      def kid
        @kid ||= thumbprint(private_key.public_key)
      end

      # The public half as a JWK Set entry, for GET /.well-known/jwks.json.
      def public_jwk
        pub = private_key.public_key
        {
          "kty" => "RSA",
          "use" => "sig",
          "alg" => ALG,
          "kid" => kid,
          "n" => b64url(pub.n.to_s(2)),
          "e" => b64url(pub.e.to_s(2))
        }
      end

      def jwks
        { "keys" => [public_jwk] }
      end

      def sign(signing_input)
        private_key.sign(OpenSSL::Digest::SHA384.new, signing_input)
      end

      # Test seam: forget the memoised key/kid so a spec can swap the key.
      def reset!
        self.cached_key = nil
        @kid = nil
      end

      private

      def load_or_generate
        pem = ENV["OIDC_SIGNING_KEY"].presence
        # Hosts that only take single-line env values (Render, etc.) carry the
        # PEM with literal "\n"; restore the real newlines OpenSSL needs.
        return OpenSSL::PKey::RSA.new(pem.gsub('\n', "\n")) if pem

        if Rails.env.production?
          Rails.logger.warn(
            "OIDC_SIGNING_KEY is not set: generating an ephemeral id_token signing key. " \
            "id_tokens will not verify across restarts or multiple instances. " \
            "Set OIDC_SIGNING_KEY to a stable RSA PEM."
          )
        end
        OpenSSL::PKey::RSA.new(2048)
      end

      def thumbprint(pub)
        json = %({"e":"#{b64url(pub.e.to_s(2))}","kty":"RSA","n":"#{b64url(pub.n.to_s(2))}"})
        b64url(OpenSSL::Digest::SHA256.digest(json))
      end

      def b64url(bytes)
        Base64.urlsafe_encode64(bytes, padding: false)
      end
    end
  end
end
