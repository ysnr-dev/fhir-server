require "rails_helper"

RSpec.describe RefreshToken do
  let(:redirect_uri) { "https://app.example/cb" }
  let(:client) do
    OauthClient.register(
      name: "app", scopes: "patient/*.read offline_access online_access",
      redirect_uris: redirect_uri, client_type: "public"
    ).first
  end
  let(:patient) do
    Patient.create!(id: SecureRandom.uuid, content: { "resourceType" => "Patient" },
                    version_id: 1, last_updated: Time.current)
  end
  let(:user) { User.create!(email: "p@example.com", patient_id: patient.id, password: "correct-horse-battery") }
  let(:code) do
    AuthorizationCode.issue(
      client: client, user: user, scopes: scopes, redirect_uri: redirect_uri,
      code_challenge: "c" * 43
    ).first
  end
  let(:scopes) { %w[patient/*.read offline_access] }

  def issue
    described_class.issue(
      client: client, user: user, patient_id: user.patient_id,
      scopes: scopes, authorization_code: code
    )
  end

  describe ".issue / .authenticate" do
    it "stores a digest and authenticates the raw token" do
      record, raw = issue

      expect(raw).to be_present
      expect(record.token_digest).not_to eq(raw)
      expect(described_class.authenticate(raw)).to eq(record)
      expect(described_class.authenticate("wrong")).to be_nil
      expect(described_class.authenticate(nil)).to be_nil
    end

    it "gives offline_access the long TTL" do
      record, = issue

      expect(record.expires_at).to be_within(1.minute).of(described_class::OFFLINE_TTL.from_now)
    end

    context "with online_access only" do
      let(:scopes) { %w[patient/*.read online_access] }

      it "gives the short TTL" do
        record, = issue

        expect(record.expires_at).to be_within(1.minute).of(described_class::ONLINE_TTL.from_now)
      end
    end
  end

  describe "#consume!" do
    it "claims the token exactly once" do
      record, = issue

      expect(record.consume!).to be(true)
      expect(record).to be_used
      expect(described_class.find(record.id).consume!).to be(false)
    end
  end

  describe "#rotate!" do
    it "issues a replacement carrying the same grant" do
      record, = issue
      rotated, raw = record.rotate!

      expect(raw).to be_present
      expect(rotated.oauth_client).to eq(client)
      expect(rotated.user).to eq(user)
      expect(rotated.patient_id).to eq(user.patient_id)
      expect(rotated.scope_list).to eq(scopes)
      expect(rotated.authorization_code).to eq(code)
      expect(rotated).not_to be_used
    end
  end

  describe "grant-wide revocation (AuthorizationCode#revoke_issued_tokens!)" do
    it "revokes refresh tokens along with access tokens" do
      record, = issue
      _access, access_raw = AccessToken.issue(client, scopes: scopes, user: user,
                                              patient_id: user.patient_id, authorization_code: code)

      code.revoke_issued_tokens!

      expect(record.reload).to be_revoked
      expect(AccessToken.authenticate(access_raw)).to be_revoked
    end
  end
end
