require "rails_helper"

RSpec.describe OauthClient do
  let(:redirect_uri) { "https://app.example/cb" }

  describe ".register" do
    it "issues a secret exactly once for a confidential backend client" do
      client, secret = described_class.register(name: "backend", scopes: "system/*.read")

      expect(client.id).to be_present
      expect(secret).to be_present
      expect(client.secret_digest).to eq(described_class.digest(secret))
      expect(client.secret_digest).not_to eq(secret)
      expect(described_class.authenticate(client.id, secret)).to eq(client)
      expect(described_class.authenticate(client.id, "wrong")).to be_nil
    end

    it "issues no secret for a JWKS client" do
      jwks = { "keys" => [{ "kty" => "RSA", "n" => "x", "e" => "AQAB" }] }
      client, secret = described_class.register(name: "jwks", scopes: "system/*.read", jwks: jwks)

      expect(secret).to be_nil
      expect(client.secret_digest).to be_nil
      expect(client.jwks).to eq(jwks)
    end

    it "issues no secret for a public launch client" do
      client, secret = described_class.register(
        name: "spa", scopes: "patient/*.read", redirect_uris: redirect_uri, client_type: "public"
      )

      expect(secret).to be_nil
      expect(client).to be_public_client
      expect(client).to be_launch_client
      expect(client.redirect_uri_list).to eq([redirect_uri])
    end

    it "accepts redirect_uris as an array and stores them space-separated" do
      client, = described_class.register(
        name: "spa", scopes: "patient/*.read",
        redirect_uris: [redirect_uri, "https://app.example/other"], client_type: "public"
      )

      expect(client.redirect_uri_list).to eq([redirect_uri, "https://app.example/other"])
      expect(client.redirect_uri_registered?(redirect_uri)).to be(true)
      # 前方一致やワイルドカードは許さない(オープンリダイレクタになる)
      expect(client.redirect_uri_registered?("https://app.example/cb/evil")).to be(false)
    end
  end

  describe "validations" do
    # name / scopes は DB が null:false だが、presence 検証が無いと
    # NotNullViolation(500) になり管理APIから 422 を返せない。
    it "requires a name" do
      client = described_class.new(id: SecureRandom.uuid, scopes: "system/*.read")

      expect(client).not_to be_valid
      expect(client.errors[:name]).to be_present
    end

    it "requires scopes" do
      client = described_class.new(id: SecureRandom.uuid, name: "no-scopes")

      expect(client).not_to be_valid
      expect(client.errors[:scopes]).to be_present
    end

    it "rejects an unknown client_type" do
      client = described_class.new(id: SecureRandom.uuid, name: "x", scopes: "system/*.read",
                                   client_type: "hybrid")

      expect(client).not_to be_valid
      expect(client.errors[:client_type]).to be_present
    end

    it "rejects an unsupported scope" do
      expect { described_class.register(name: "x", scopes: "user/*.read") }
        .to raise_error(ActiveRecord::RecordInvalid, /unsupported scope/)
    end

    it "rejects mixing system/ and patient/ scopes" do
      expect { described_class.register(name: "x", scopes: "system/*.read patient/*.read",
                                        redirect_uris: redirect_uri) }
        .to raise_error(ActiveRecord::RecordInvalid, /cannot mix/)
    end

    it "rejects patient/ write scopes" do
      expect { described_class.register(name: "x", scopes: "patient/Observation.write",
                                        redirect_uris: redirect_uri) }
        .to raise_error(ActiveRecord::RecordInvalid, /unsupported scope/)
    end

    it "rejects context scopes without a patient/ scope" do
      expect { described_class.register(name: "x", scopes: "system/*.read offline_access") }
        .to raise_error(ActiveRecord::RecordInvalid, /offline_access/)
    end

    it "requires redirect_uris for patient/ scopes" do
      expect { described_class.register(name: "x", scopes: "patient/*.read") }
        .to raise_error(ActiveRecord::RecordInvalid, /redirect/i)
    end

    it "rejects redirect_uris on a system/ client" do
      expect { described_class.register(name: "x", scopes: "system/*.read", redirect_uris: redirect_uri) }
        .to raise_error(ActiveRecord::RecordInvalid, /must be patient/)
    end

    it "rejects a JWKS on a public client" do
      expect do
        described_class.register(
          name: "x", scopes: "patient/*.read", redirect_uris: redirect_uri,
          client_type: "public", jwks: { "keys" => [] }
        )
      end.to raise_error(ActiveRecord::RecordInvalid, /jwks/i)
    end
  end

  describe "#destroy" do
    let(:client) do
      described_class.register(
        name: "app", scopes: "patient/*.read offline_access",
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
        client: client, user: user, scopes: %w[patient/*.read offline_access],
        redirect_uri: redirect_uri, code_challenge: "c" * 43
      ).first
    end

    before do
      AccessToken.issue(client, scopes: %w[patient/*.read], user: user,
                                patient_id: user.patient_id, authorization_code: code)
      RefreshToken.issue(client: client, user: user, patient_id: user.patient_id,
                         scopes: %w[patient/*.read offline_access], authorization_code: code)
      ClientAssertionJti.register(client.id, SecureRandom.uuid, 5.minutes.from_now)
    end

    it "removes every dependent credential" do
      expect { client.destroy! }
        .to change(AccessToken, :count).by(-1)
        .and change(RefreshToken, :count).by(-1)
        .and change(AuthorizationCode, :count).by(-1)
        .and change(ClientAssertionJti, :count).by(-1)
    end

    it "detaches bulk exports rather than deleting the history" do
      export = BulkExport.create!(
        id: SecureRandom.uuid, kind: "system", output_format: "application/fhir+ndjson",
        request_url: "http://localhost/$export", oauth_client_id: client.id
      )

      expect { client.destroy! }.not_to change(BulkExport, :count)
      expect(export.reload.oauth_client_id).to be_nil
    end
  end
end
