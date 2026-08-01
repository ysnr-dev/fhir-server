require "rails_helper"

RSpec.describe "PractitionerRoles", type: :request do
  describe "POST /PractitionerRole" do
    it "creates and returns 201 with Location header, ETag, and meta" do
      post "/PractitionerRole", params: valid_practitioner_role_payload, as: :json

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to match(%r{/PractitionerRole/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("PractitionerRole")
    end

    it "returns 422 for a non-boolean active" do
      post "/PractitionerRole", params: valid_practitioner_role_payload(active: "yes"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "read, update, delete, history" do
    it "supports the full lifecycle" do
      post "/PractitionerRole", params: valid_practitioner_role_payload, as: :json
      id = JSON.parse(response.body)["id"]

      get "/PractitionerRole/#{id}"
      expect(response).to have_http_status(:ok)

      put "/PractitionerRole/#{id}", params: valid_practitioner_role_payload(active: false), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/PractitionerRole/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/PractitionerRole/#{id}/_history"
      expect(JSON.parse(response.body)["total"]).to eq(3)
    end
  end

  describe "GET /PractitionerRole (search)" do
    it "finds by practitioner reference" do
      practitioner_id = SecureRandom.uuid
      post "/PractitionerRole",
           params: valid_practitioner_role_payload(practitioner: { "reference" => "Practitioner/#{practitioner_id}" }),
           as: :json

      get "/PractitionerRole", params: { practitioner: "Practitioner/#{practitioner_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "filters by specialty and active" do
      post "/PractitionerRole", params: valid_practitioner_role_payload, as: :json

      get "/PractitionerRole", params: { specialty: "394814009", active: "true" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to be >= 1
    end

    # fhir-client の医療従事者選択モーダルが「職種・所属で絞りつつ氏名(カナ含む)を
    # チェーン検索でサーバー側に寄せ、_include で Practitioner 本体も受け取る」
    # クエリ形に依存するため、この組み合わせを固定する。
    it "chains practitioner.name:contains (kana included) and includes the practitioner" do
      post "/Practitioner", params: valid_practitioner_payload, as: :json
      suzuki_id = JSON.parse(response.body)["id"]
      post "/Practitioner",
           params: valid_practitioner_payload("name" => [{ "use" => "official", "family" => "田中", "given" => ["花子"] }]),
           as: :json
      tanaka_id = JSON.parse(response.body)["id"]

      post "/PractitionerRole",
           params: valid_practitioner_role_payload(practitioner: { "reference" => "Practitioner/#{suzuki_id}" }),
           as: :json
      suzuki_role_id = JSON.parse(response.body)["id"]
      post "/PractitionerRole",
           params: valid_practitioner_role_payload(practitioner: { "reference" => "Practitioner/#{tanaka_id}" }),
           as: :json

      get "/PractitionerRole?role=doctor" \
          "&practitioner.name:contains=#{Rack::Utils.escape('ズキ')}" \
          "&_include=PractitionerRole:practitioner"

      bundle = JSON.parse(response.body)
      modes = bundle["entry"].group_by { |e| e.dig("search", "mode") }
      expect(modes["match"].map { |e| e.dig("resource", "id") }).to eq([suzuki_role_id])
      expect(modes["include"].map { |e| e.dig("resource", "id") }).to eq([suzuki_id])
    end
  end
end
