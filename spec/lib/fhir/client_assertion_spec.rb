require "rails_helper"

RSpec.describe Fhir::ClientAssertion do
  AUDIENCE = "http://www.example.com/oauth/token".freeze

  def b64url(data)
    Base64.urlsafe_encode64(data, padding: false)
  end

  def rsa_jwk(key, kid: "key-1")
    {
      "kty" => "RSA", "kid" => kid, "alg" => "RS384", "use" => "sig",
      "n" => b64url(key.n.to_s(2)),
      "e" => b64url(key.e.to_s(2))
    }
  end

  def ec_jwk(key, kid: "key-1")
    point = key.public_key.to_octet_string(:uncompressed) # 0x04 || x || y
    {
      "kty" => "EC", "kid" => kid, "alg" => "ES384", "crv" => "P-384", "use" => "sig",
      "x" => b64url(point[1, 48]),
      "y" => b64url(point[49, 48])
    }
  end

  def sign_jwt(key, alg:, kid:, claims:)
    header = { "alg" => alg, "typ" => "JWT", "kid" => kid }
    input = "#{b64url(header.to_json)}.#{b64url(claims.to_json)}"
    signature =
      if alg == "RS384"
        key.sign(OpenSSL::Digest::SHA384.new, input)
      else
        der = key.sign(OpenSSL::Digest::SHA384.new, input)
        sequence = OpenSSL::ASN1.decode(der)
        r, s = sequence.value.map { |bn| bn.value.to_s(2) }
        r.rjust(48, "\x00") + s.rjust(48, "\x00")
      end
    "#{input}.#{b64url(signature)}"
  end

  def default_claims(client_id, overrides = {})
    {
      "iss" => client_id, "sub" => client_id, "aud" => AUDIENCE,
      "exp" => 4.minutes.from_now.to_i, "jti" => SecureRandom.uuid
    }.merge(overrides)
  end

  def verify(assertion, type: described_class::JWT_BEARER_TYPE)
    described_class.call(assertion, assertion_type: type, audience: AUDIENCE)
  end

  let(:rsa_private_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:rsa_client) { OauthClient.register(name: "rsa-client", scopes: "system/*.read", jwks: { "keys" => [rsa_jwk(rsa_private_key)] }).first }

  it "authenticates a valid RS384 assertion" do
    assertion = sign_jwt(rsa_private_key, alg: "RS384", kid: "key-1", claims: default_claims(rsa_client.id))

    result = verify(assertion)

    expect(result).to be_valid
    expect(result.client.id).to eq(rsa_client.id)
  end

  it "authenticates a valid ES384 assertion" do
    ec_key = OpenSSL::PKey::EC.generate("secp384r1")
    client = OauthClient.register(name: "ec-client", scopes: "system/*.read", jwks: { "keys" => [ec_jwk(ec_key)] }).first

    assertion = sign_jwt(ec_key, alg: "ES384", kid: "key-1", claims: default_claims(client.id))

    expect(verify(assertion)).to be_valid
  end

  it "rejects a signature from the wrong key" do
    other_key = OpenSSL::PKey::RSA.new(2048)
    assertion = sign_jwt(other_key, alg: "RS384", kid: "key-1", claims: default_claims(rsa_client.id))

    result = verify(assertion)

    expect(result).not_to be_valid
    expect(result.error_description).to include("Signature verification failed")
  end

  it "rejects a replayed jti" do
    claims = default_claims(rsa_client.id)
    assertion = sign_jwt(rsa_private_key, alg: "RS384", kid: "key-1", claims: claims)

    expect(verify(assertion)).to be_valid
    result = verify(assertion)
    expect(result).not_to be_valid
    expect(result.error_description).to include("replay")
  end

  it "rejects expired assertions and ones valid too far into the future" do
    expired = sign_jwt(rsa_private_key, alg: "RS384", kid: "key-1",
                       claims: default_claims(rsa_client.id, "exp" => 5.minutes.ago.to_i))
    expect(verify(expired).error_description).to include("expired")

    too_long = sign_jwt(rsa_private_key, alg: "RS384", kid: "key-1",
                        claims: default_claims(rsa_client.id, "exp" => 30.minutes.from_now.to_i))
    expect(verify(too_long).error_description).to include("5 minutes")
  end

  it "rejects claim violations: wrong aud, iss/sub mismatch, missing jti, unknown client" do
    wrong_aud = sign_jwt(rsa_private_key, alg: "RS384", kid: "key-1",
                         claims: default_claims(rsa_client.id, "aud" => "https://other.example.com/token"))
    expect(verify(wrong_aud).error_description).to include("aud")

    mismatch = sign_jwt(rsa_private_key, alg: "RS384", kid: "key-1",
                        claims: default_claims(rsa_client.id, "sub" => "someone-else"))
    expect(verify(mismatch).error_description).to include("iss and sub")

    no_jti = sign_jwt(rsa_private_key, alg: "RS384", kid: "key-1",
                      claims: default_claims(rsa_client.id).except("jti"))
    expect(verify(no_jti).error_description).to include("jti")

    unknown = sign_jwt(rsa_private_key, alg: "RS384", kid: "key-1", claims: default_claims("no-such-client"))
    expect(verify(unknown).error_description).to include("Unknown client")
  end

  it "rejects unsupported algorithms and malformed tokens" do
    header = { "alg" => "HS256", "typ" => "JWT" }
    input = "#{b64url(header.to_json)}.#{b64url(default_claims(rsa_client.id).to_json)}"
    hs256 = "#{input}.#{b64url(OpenSSL::HMAC.digest('SHA256', 'secret', input))}"
    expect(verify(hs256).error_description).to include("Unsupported signing algorithm")

    expect(verify("not-a-jwt").error_description).to include("not a well-formed JWT")
    expect(verify(nil, type: "wrong-type").error_description).to include("client_assertion_type")
  end

  it "rejects an assertion whose kid matches no registered key" do
    assertion = sign_jwt(rsa_private_key, alg: "RS384", kid: "other-kid", claims: default_claims(rsa_client.id))

    expect(verify(assertion).error_description).to include("No usable key")
  end

  it "rejects assertions from a secret-based client (no JWKS registered)" do
    secret_client, = OauthClient.register(name: "secret-client", scopes: "system/*.read")
    assertion = sign_jwt(rsa_private_key, alg: "RS384", kid: "key-1", claims: default_claims(secret_client.id))

    expect(verify(assertion).error_description).to include("no registered JWKS")
  end
end
