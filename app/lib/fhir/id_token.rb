module Fhir
  # Builds a signed OpenID Connect id_token for the interactive launches, per
  # SMART App Launch's identity layer. Issued only when the granted scopes
  # include `openid`; the identity claims beyond `sub` are gated on the
  # `fhirUser` / `profile` scopes.
  #
  #   sub       stable, issuer-local user identifier: the User row id for a
  #             patient, "Practitioner/{id}" for an EHR-launched practitioner
  #             (prefixed so the two namespaces can never collide)
  #   fhirUser  absolute URL of the FHIR resource the user *is* -- the launch
  #             Patient, or the launching Practitioner. Present with `fhirUser`
  #             or `profile` scope.
  #   nonce     echoed from the authorization request when the client sent one
  #
  # Signed RS384 with Fhir::SigningKey; verifiable against /.well-known/jwks.json.
  class IdToken
    TTL = 1.hour

    def self.issue(client:, scopes:, issuer:, user: nil, patient_id: nil, practitioner_id: nil, nonce: nil)
      new(user:, patient_id:, practitioner_id:, client:, scopes:, issuer:, nonce:).issue
    end

    def initialize(user:, patient_id:, practitioner_id:, client:, scopes:, issuer:, nonce:)
      @user = user
      @patient_id = patient_id
      @practitioner_id = practitioner_id
      @client = client
      @scopes = scopes
      @issuer = issuer
      @nonce = nonce
    end

    def issue
      now = Time.current.to_i
      claims = {
        "iss" => @issuer,
        "sub" => subject,
        "aud" => @client.id,
        "iat" => now,
        "exp" => now + TTL.to_i
      }
      if fhir_user_requested?
        fhir_user = "#{@issuer}/#{fhir_user_path}"
        # `profile` is the OIDC-legacy name for the same value SMART now carries
        # in `fhirUser`; emit both so either style of client resolves the user.
        claims["fhirUser"] = fhir_user
        claims["profile"] = fhir_user
      end
      claims["nonce"] = @nonce if @nonce.present?

      encode(claims)
    end

    private

    def subject
      @practitioner_id.present? ? "Practitioner/#{@practitioner_id}" : @user.id.to_s
    end

    def fhir_user_path
      @practitioner_id.present? ? "Practitioner/#{@practitioner_id}" : "Patient/#{@patient_id}"
    end

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
