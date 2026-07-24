require "rails_helper"

RSpec.describe Fhir::IdToken do
  let(:patient) do
    Patient.create!(id: SecureRandom.uuid, content: { "resourceType" => "Patient" },
                    version_id: 1, last_updated: Time.current)
  end
  let(:user) { User.create!(email: "p@example.com", patient_id: patient.id, password: "correct-horse-battery") }
  let(:client) do
    OauthClient.register(
      name: "app", scopes: "patient/*.read openid fhirUser",
      redirect_uris: "https://app.example/cb", client_type: "public"
    ).first
  end
  let(:issuer) { "https://fhir.example" }

  def issue(scopes:, nonce: nil)
    Fhir::IdToken.issue(user: user, patient_id: patient.id, client: client,
                        scopes: scopes, issuer: issuer, nonce: nonce)
  end

  it "signs claims that verify against the published JWK" do
    token = issue(scopes: %w[patient/*.read openid])
    _header, claims = decode_jwt(token)

    expect(jwt_signature_valid?(token, Fhir::SigningKey.public_jwk)).to be(true)
    expect(claims["iss"]).to eq(issuer)
    expect(claims["sub"]).to eq(user.id.to_s)
    expect(claims["aud"]).to eq(client.id)
    expect(claims["exp"]).to be > claims["iat"]
  end

  it "sets the header alg and kid to the signing key's" do
    header, = decode_jwt(issue(scopes: %w[openid]))

    expect(header).to include("alg" => "RS384", "typ" => "JWT", "kid" => Fhir::SigningKey.kid)
  end

  describe "fhirUser claim" do
    it "is present as an absolute Patient URL with fhirUser scope" do
      _header, claims = decode_jwt(issue(scopes: %w[openid fhirUser]))

      expect(claims["fhirUser"]).to eq("#{issuer}/Patient/#{patient.id}")
      expect(claims["profile"]).to eq("#{issuer}/Patient/#{patient.id}")
    end

    it "is also emitted for the legacy profile scope" do
      _header, claims = decode_jwt(issue(scopes: %w[openid profile]))

      expect(claims["fhirUser"]).to eq("#{issuer}/Patient/#{patient.id}")
    end

    it "is absent when only openid was requested" do
      _header, claims = decode_jwt(issue(scopes: %w[openid]))

      expect(claims).not_to have_key("fhirUser")
      expect(claims).not_to have_key("profile")
    end
  end

  describe "nonce" do
    it "is echoed when the authorization request carried one" do
      _header, claims = decode_jwt(issue(scopes: %w[openid], nonce: "n-0S6_WzA2Mj"))

      expect(claims["nonce"]).to eq("n-0S6_WzA2Mj")
    end

    it "is omitted when there was none" do
      _header, claims = decode_jwt(issue(scopes: %w[openid]))

      expect(claims).not_to have_key("nonce")
    end
  end
end
