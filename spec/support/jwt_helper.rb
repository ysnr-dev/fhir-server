# Decoding and verifying the JWTs this server issues (id_tokens), from a
# client's point of view: split, parse, and check the RS384 signature against
# a JWK published at /.well-known/jwks.json.
module JwtHelper
  # Returns [header, claims] without verifying -- for inspecting structure.
  def decode_jwt(token)
    header, claims, = token.split(".")
    [JSON.parse(b64url_decode(header)), JSON.parse(b64url_decode(claims))]
  end

  # True when the token's signature verifies against the given JWK.
  def jwt_signature_valid?(token, jwk)
    header_b64, claims_b64, signature_b64 = token.split(".")
    signing_input = "#{header_b64}.#{claims_b64}"
    key = rsa_key_from_jwk(jwk)
    key.verify(OpenSSL::Digest::SHA384.new, b64url_decode(signature_b64), signing_input)
  end

  def rsa_key_from_jwk(jwk)
    n = OpenSSL::BN.new(b64url_decode(jwk["n"]), 2)
    e = OpenSSL::BN.new(b64url_decode(jwk["e"]), 2)
    der = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer(n), OpenSSL::ASN1::Integer(e)]).to_der
    OpenSSL::PKey::RSA.new(der)
  end

  def b64url_decode(str)
    Base64.urlsafe_decode64(str + "=" * ((4 - str.length % 4) % 4))
  end
end

RSpec.configure { |config| config.include JwtHelper }
