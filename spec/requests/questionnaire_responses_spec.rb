require "rails_helper"

RSpec.describe "QuestionnaireResponse", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_practitioner
    post "/Practitioner", params: valid_practitioner_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "create" do
    it "creates a valid response with 201" do
      patient_id = create_patient

      post "/QuestionnaireResponse", params: valid_questionnaire_response_payload(subject_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["meta"]["versionId"]).to eq("1")
      expect(body["meta"]["profile"])
        .to eq(["http://www.hosp.ncgm.go.jp/JASPEHR/fhir/StructureDefinition/jaspehr-questionnaireresponse"])
    end

    it "returns 422 when a JASPEHR-mandatory element is missing" do
      patient_id = create_patient
      payload = valid_questionnaire_response_payload(subject_id: patient_id)

      %w[identifier questionnaire status subject authored author].each do |field|
        post "/QuestionnaireResponse", params: payload.except(field), as: :json
        expect(response).to have_http_status(:unprocessable_content), "expected #{field} to be required"
      end
    end

    it "returns 422 when the subject references a non-existent Patient" do
      post "/QuestionnaireResponse", params: valid_questionnaire_response_payload(subject_id: "does-not-exist"),
                                     as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for a malformed 医療機関番号 in the JP eCS extension" do
      patient_id = create_patient
      payload = valid_questionnaire_response_payload(subject_id: patient_id)
      payload["extension"][0]["valueIdentifier"]["value"] = "9999999999"

      post "/QuestionnaireResponse", params: payload, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("institutionNumberExtension")
    end
  end

  describe "read / update / delete lifecycle" do
    it "supports the full instance lifecycle" do
      patient_id = create_patient
      post "/QuestionnaireResponse", params: valid_questionnaire_response_payload(subject_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/QuestionnaireResponse/#{id}"
      expect(response).to have_http_status(:ok)

      put "/QuestionnaireResponse/#{id}",
          params: valid_questionnaire_response_payload(subject_id: patient_id, "status" => "amended"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/QuestionnaireResponse/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/QuestionnaireResponse/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "search" do
    def total
      JSON.parse(response.body)["total"]
    end

    it "finds responses by patient, status, questionnaire, author, and authored" do
      patient_id = create_patient
      other_id = create_patient
      practitioner_id = create_practitioner

      post "/QuestionnaireResponse",
           params: valid_questionnaire_response_payload(subject_id: patient_id, author_id: practitioner_id), as: :json
      post "/QuestionnaireResponse",
           params: valid_questionnaire_response_payload(subject_id: other_id, "status" => "amended"), as: :json

      get "/QuestionnaireResponse?patient=#{patient_id}"
      expect(total).to eq(1)

      get "/QuestionnaireResponse?subject=Patient/#{other_id}"
      expect(total).to eq(1)

      get "/QuestionnaireResponse?status=completed"
      expect(total).to eq(1)

      get "/QuestionnaireResponse?author=#{practitioner_id}"
      expect(total).to eq(1)

      get "/QuestionnaireResponse?authored=ge2026-07-01&authored=le2026-08-01"
      expect(total).to eq(2)
    end

    it "accepts a date-only authored and finds it by that exact date" do
      patient_id = create_patient
      post "/QuestionnaireResponse",
           params: valid_questionnaire_response_payload(subject_id: patient_id, "authored" => "2026-08-01"), as: :json
      expect(response).to have_http_status(:created)

      get "/QuestionnaireResponse?authored=2026-08-01"
      expect(total).to eq(1)

      get "/QuestionnaireResponse?authored=2026-08-02"
      expect(total).to eq(0)
    end

    it "matches the questionnaire canonical exactly, version included" do
      patient_id = create_patient
      post "/QuestionnaireResponse", params: valid_questionnaire_response_payload(subject_id: patient_id), as: :json

      get "/QuestionnaireResponse", params: { questionnaire: "http://example.org/Questionnaire/jaspehr-example|1.0.0" }
      expect(total).to eq(1)

      get "/QuestionnaireResponse", params: { questionnaire: "http://example.org/Questionnaire/jaspehr-example" }
      expect(total).to eq(0)
    end

    it "finds responses by identifier" do
      patient_id = create_patient
      post "/QuestionnaireResponse", params: valid_questionnaire_response_payload(subject_id: patient_id), as: :json

      get "/QuestionnaireResponse?identifier=http://example.org/questionnaire-response|1311234567^P0001^R0001"
      expect(total).to eq(1)
    end

    it "matches 0..* basedOn references by jsonb containment" do
      patient_id = create_patient
      payload = valid_questionnaire_response_payload(
        subject_id: patient_id, "basedOn" => [{ "reference" => "ServiceRequest/sr-1" }]
      )
      post "/QuestionnaireResponse", params: payload, as: :json
      post "/QuestionnaireResponse", params: valid_questionnaire_response_payload(subject_id: patient_id), as: :json

      get "/QuestionnaireResponse?based-on=ServiceRequest/sr-1"
      expect(total).to eq(1)
    end

    it "resolves _include:subject to the Patient" do
      patient_id = create_patient
      post "/QuestionnaireResponse", params: valid_questionnaire_response_payload(subject_id: patient_id), as: :json

      get "/QuestionnaireResponse?_include=QuestionnaireResponse:patient"

      types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
      expect(types).to contain_exactly("QuestionnaireResponse", "Patient")
    end

    # questionnaire は canonical("url|version" 文字列)。Reference の traverse では
    # なく Questionnaire の url(+version) 検索で解決される専用の _include。
    describe "_include=QuestionnaireResponse:questionnaire (canonical)" do
      def included_entries
        JSON.parse(response.body)["entry"].to_a.select { |e| e.dig("search", "mode") == "include" }
      end

      it "includes exactly the version the canonical pins" do
        post "/Questionnaire", params: valid_questionnaire_payload, as: :json
        pinned_id = JSON.parse(response.body)["id"]
        post "/Questionnaire", params: valid_questionnaire_payload("version" => "2.0.0"), as: :json

        patient_id = create_patient
        post "/QuestionnaireResponse", params: valid_questionnaire_response_payload(subject_id: patient_id), as: :json

        get "/QuestionnaireResponse?_include=QuestionnaireResponse:questionnaire"

        expect(included_entries.map { |e| e.dig("resource", "id") }).to eq([pinned_id])
        expect(included_entries.first.dig("resource", "resourceType")).to eq("Questionnaire")
      end

      it "includes every version for a bare (version-less) canonical" do
        post "/Questionnaire", params: valid_questionnaire_payload, as: :json
        post "/Questionnaire", params: valid_questionnaire_payload("version" => "2.0.0"), as: :json

        patient_id = create_patient
        post "/QuestionnaireResponse",
             params: valid_questionnaire_response_payload(
               subject_id: patient_id, "questionnaire" => "http://example.org/Questionnaire/jaspehr-example"
             ), as: :json

        get "/QuestionnaireResponse?_include=QuestionnaireResponse:questionnaire"

        versions = included_entries.map { |e| e.dig("resource", "version") }
        expect(versions).to contain_exactly("1.0.0", "2.0.0")
      end

      it "adds nothing when the canonical matches no Questionnaire" do
        patient_id = create_patient
        post "/QuestionnaireResponse", params: valid_questionnaire_response_payload(subject_id: patient_id), as: :json

        get "/QuestionnaireResponse?_include=QuestionnaireResponse:questionnaire"

        expect(response).to have_http_status(:ok)
        expect(included_entries).to be_empty
      end

      it "accepts the typed token form" do
        post "/Questionnaire", params: valid_questionnaire_payload, as: :json
        patient_id = create_patient
        post "/QuestionnaireResponse", params: valid_questionnaire_response_payload(subject_id: patient_id), as: :json

        get "/QuestionnaireResponse?_include=QuestionnaireResponse:questionnaire:Questionnaire"

        expect(included_entries.size).to eq(1)
      end

      it "silently ignores the meaningless reverse form" do
        post "/Questionnaire", params: valid_questionnaire_payload, as: :json

        get "/Questionnaire?_revinclude=QuestionnaireResponse:questionnaire"

        expect(response).to have_http_status(:ok)
        expect(included_entries).to be_empty
      end
    end
  end

  it "joins the patient compartment ($everything)" do
    patient_id = create_patient
    post "/QuestionnaireResponse", params: valid_questionnaire_response_payload(subject_id: patient_id), as: :json

    get "/Patient/#{patient_id}/$everything"

    types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
    expect(types).to contain_exactly("Patient", "QuestionnaireResponse")
  end
end
