module Fhir
  # Builds a signed OpenID Connect id_token for the interactive launch, per
  # SMART App Launch's identity layer. Issued only when the consented scopes
  # include `openid`; the identity claims beyond `sub` are gated on the
  # `fhirUser` / `profile` scopes.
  #
  #   sub       stable, issuer-local user identifier (the User row id)
  #   fhirUser  absolute URL of the FHIR resource the user *is* -- here always
  #             the launch Patient. Present with `fhirUser` or `profile` scope.
  #   nonce     echoed from the authorization request when the client sent one
  #
  # Signed RS384 with Fhir::SigningKey; verifiable against /.well-known/jwks.json.
  class IdToken
    TTL = 1.hour

    def self.issue(user:, patient_id:, client:, scopes:, issuer:, nonce: nil)
      new(user:, patient_id:, client:, scopes:, issuer:, nonce:).issue
    end

    def initialize(user:, patient_id:, client:, scopes:, issuer:, nonce:)
      @user = user
      @patient_id = patient_id
      @client = client
      @scopes = scopes
      @issuer = issuer
      @nonce = nonce
    end

    def issue
      now = Time.current.to_i
      claims = {
        "iss" => @issuer,
        "sub" => @user.id.to_s,
        "aud" => @client.id,
        "iat" => now,
        "exp" => now + TTL.to_i
      }
      if fhir_user_requested?
        fhir_user = "#{@issuer}/Patient/#{@patient_id}"
        # `profile` is the OIDC-legacy name for the same value SMART now carries
        # in `fhirUser`; emit both so either style of client resolves the user.
        claims["fhirUser"] = fhir_user
        claims["profile"] = fhir_user
      end
      claims["nonce"] = @nonce if @nonce.present?

      encode(claims)
    end

    private

    def fhir_user_requested?
      @scopes.include?("fhirUser") || @scopes.include?("profile")
    end

    def encode(claims)
      header = { "alg" => SigningKey::ALG, "typ" => "JWT", "kid" => SigningKey.kid }
      signing_input = "#{b64url(header.to_json)}.#{b64url(claims.to_json)}"
      "#{signing_input}.#{b64url(SigningKey.sign(signing_input))}"
    end

    def b64url(data)
      Base64.urlsafe_encode64(data, padding: false)
    end
  end
end
