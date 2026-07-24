require "rails_helper"

RSpec.describe Fhir::SigningKey do
  # A fixed key so kid/JWK assertions are deterministic. Restore whatever the
  # process had memoised afterwards, since the key is global state.
  let(:pem) { OpenSSL::PKey::RSA.new(2048).to_pem }

  before do
    described_class.reset!
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OIDC_SIGNING_KEY").and_return(pem)
  end

  after { described_class.reset! }

  describe ".private_key" do
    it "loads the PEM from OIDC_SIGNING_KEY" do
      expect(described_class.private_key.to_pem).to eq(pem)
    end

    it "memoises across calls" do
      expect(described_class.private_key).to be(described_class.private_key)
    end

    it "restores escaped newlines from a single-line env value" do
      described_class.reset!
      allow(ENV).to receive(:[]).with("OIDC_SIGNING_KEY").and_return(pem.gsub("\n", '\n'))

      expect(described_class.private_key.to_pem).to eq(pem)
    end
  end

  describe ".kid" do
    it "is a stable RFC 7638 thumbprint of the public key" do
      first = described_class.kid
      described_class.reset!
      expect(described_class.kid).to eq(first)
      expect(first).to match(/\A[A-Za-z0-9_-]+\z/) # base64url, no padding
    end
  end

  describe ".public_jwk / .jwks" do
    it "exposes only the public parameters, tagged for signing" do
      jwk = described_class.public_jwk

      expect(jwk).to include("kty" => "RSA", "use" => "sig", "alg" => "RS384", "kid" => described_class.kid)
      expect(jwk).to have_key("n")
      expect(jwk).to have_key("e")
      expect(jwk).not_to have_key("d") # never leak the private exponent
      expect(described_class.jwks["keys"]).to eq([jwk])
    end
  end

  describe ".sign" do
    it "produces an RS384 signature the published public key verifies" do
      input = "header.payload"
      signature = described_class.sign(input)

      pub = rsa_key_from_jwk(described_class.public_jwk)
      expect(pub.verify(OpenSSL::Digest::SHA384.new, signature, input)).to be(true)
      expect(pub.verify(OpenSSL::Digest::SHA384.new, signature, "tampered")).to be(false)
    end
  end
end
