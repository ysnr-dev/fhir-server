require "rails_helper"

RSpec.describe AuthorizationCode do
  let(:patient) { Patient.create!(id: SecureRandom.uuid, content: { "resourceType" => "Patient" }, version_id: 1, last_updated: Time.current) }
  let(:user) { User.create!(email: "p@example.com", patient_id: patient.id, password: "correct-horse-battery") }
  let(:client) do
    OauthClient.register(
      name: "app", scopes: "patient/*.read", redirect_uris: "https://app.example/cb", client_type: "public"
    ).first
  end

  def issue(challenge: verifier_challenge, **overrides)
    described_class.issue(
      client: client, user: user, scopes: ["patient/*.read"],
      redirect_uri: "https://app.example/cb", code_challenge: challenge, **overrides
    )
  end

  let(:verifier) { "a" * 64 }
  let(:verifier_challenge) { Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false) }

  describe ".issue" do
    it "stores only a digest and freezes the patient context" do
      record, raw = issue

      expect(raw).to be_present
      expect(described_class.pluck(:code_digest)).not_to include(raw)
      expect(record.code_digest).to eq(OauthClient.digest(raw))
      expect(record.patient_id).to eq(patient.id)
    end

    it "expires in five minutes" do
      record, = issue

      expect(record.expires_at).to be_within(5.seconds).of(described_class::TTL.from_now)
    end
  end

  describe ".authenticate" do
    it "finds a code by its raw value and rejects anything else" do
      record, raw = issue

      expect(described_class.authenticate(raw)).to eq(record)
      expect(described_class.authenticate("nope")).to be_nil
      expect(described_class.authenticate(nil)).to be_nil
    end
  end

  describe "#consume!" do
    # Concurrent redemptions must not both succeed -- the loser is treated as a
    # replay by the token endpoint.
    it "succeeds exactly once" do
      record, = issue

      expect(record.consume!).to be(true)
      expect(record.consume!).to be(false)
      expect(record.reload).to be_used
    end
  end

  describe "#pkce_valid?" do
    it "accepts the verifier that produced the challenge" do
      record, = issue

      expect(record.pkce_valid?(verifier)).to be(true)
    end

    it "rejects a different verifier" do
      record, = issue

      expect(record.pkce_valid?("b" * 64)).to be(false)
    end

    it "rejects a malformed verifier before hashing it" do
      record, = issue

      expect(record.pkce_valid?("too-short")).to be(false)          # under 43 chars
      expect(record.pkce_valid?("a" * 129)).to be(false)            # over 128
      expect(record.pkce_valid?("#{'a' * 43}!")).to be(false)       # reserved character
      expect(record.pkce_valid?(nil)).to be(false)
    end

    it "rejects anything but S256" do
      record, = issue(code_challenge_method: "plain")

      expect(record.pkce_valid?(verifier)).to be(false)
    end
  end

  describe "#revoke_issued_tokens!" do
    it "revokes the tokens the code produced" do
      record, = issue
      token, = AccessToken.issue(client, scopes: ["patient/*.read"], user: user,
                                         patient_id: patient.id, authorization_code: record)

      record.revoke_issued_tokens!

      expect(token.reload).to be_revoked
    end
  end
end
