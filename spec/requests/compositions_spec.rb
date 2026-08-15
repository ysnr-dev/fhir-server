require "rails_helper"

RSpec.describe "Composition", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "create" do
    it "creates a valid composition with 201" do
      patient_id = create_patient

      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["meta"]["versionId"]).to eq("1")
      expect(body["meta"]["profile"]).to eq(["http://hl7.org/fhir/StructureDefinition/Composition"])
    end

    it "returns 422 when status is missing or invalid" do
      patient_id = create_patient

      post "/Composition", params: valid_composition_payload(subject_id: patient_id).except("status"), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      post "/Composition", params: valid_composition_payload(subject_id: patient_id, status: "draft"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when author is missing" do
      patient_id = create_patient

      post "/Composition", params: valid_composition_payload(subject_id: patient_id).except("author"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when the subject references a non-existent Patient" do
      post "/Composition", params: valid_composition_payload(subject_id: "does-not-exist"), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "read / update / delete lifecycle" do
    it "supports the full instance lifecycle" do
      patient_id = create_patient
      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Composition/#{id}"
      expect(response).to have_http_status(:ok)

      put "/Composition/#{id}", params: valid_composition_payload(subject_id: patient_id, status: "amended"), as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/Composition/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Composition/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "search" do
    it "finds compositions by patient, status, type, category, and date" do
      patient_id = create_patient
      other_id = create_patient
      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json
      post "/Composition", params: valid_composition_payload(subject_id: other_id, status: "preliminary"), as: :json

      get "/Composition?patient=#{patient_id}"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Composition?status=final"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Composition?type=18842-5"
      expect(JSON.parse(response.body)["total"]).to eq(2)

      get "/Composition?category=11488-4"
      expect(JSON.parse(response.body)["total"]).to eq(2)

      get "/Composition?date=ge2026-07-01&date=le2026-08-01"
      expect(JSON.parse(response.body)["total"]).to eq(2)
    end

    it "finds compositions by identifier" do
      patient_id = create_patient
      post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json

      get "/Composition?identifier=http://example.org/composition|COMP1"
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # POS/POMR のカルテを 1 つのプロブレムで縦に読むための絞り込み。対象疾患は
    # base Composition に置き場が無くローカル拡張に入るため、標準外のパラメータで引く。
    describe "problem" do
      let(:problem_url) { "http://fhir-client.local/StructureDefinition/clinical-note-problem" }
      let(:other_url) { "http://fhir-client.local/StructureDefinition/some-other-reference" }

      def create_with_extension(patient_id, extension)
        post "/Composition",
             params: valid_composition_payload(subject_id: patient_id).merge("extension" => extension),
             as: :json
        expect(response).to have_http_status(:created)
        JSON.parse(response.body)["id"]
      end

      def problem_extension(condition_id)
        [{ "url" => problem_url, "valueReference" => { "reference" => "Condition/#{condition_id}" } }]
      end

      it "finds the notes written against one problem" do
        patient_id = create_patient
        target_id = create_with_extension(patient_id, problem_extension("c1"))
        create_with_extension(patient_id, problem_extension("c2"))

        get "/Composition", params: { problem: "Condition/c1" }

        bundle = JSON.parse(response.body)
        expect(bundle["entry"].map { |e| e["resource"]["id"] }).to eq([target_id])
      end

      it "qualifies a bare id as a Condition" do
        patient_id = create_patient
        target_id = create_with_extension(patient_id, problem_extension("c1"))

        get "/Composition", params: { problem: "c1" }

        expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([target_id])
      end

      # 一致条件に url を入れていないと、同じ参照を持つ別の拡張まで拾ってしまう。
      it "ignores a different extension carrying the same reference" do
        patient_id = create_patient
        create_with_extension(
          patient_id,
          [{ "url" => other_url, "valueReference" => { "reference" => "Condition/c1" } }]
        )

        get "/Composition", params: { problem: "Condition/c1" }

        expect(JSON.parse(response.body)["total"]).to eq(0)
      end

      it "supports problem:missing" do
        patient_id = create_patient
        linked_id = create_with_extension(patient_id, problem_extension("c1"))
        # 別の拡張だけを持つ記録は「プロブレム未設定」に数える。
        unlinked_id = create_with_extension(
          patient_id,
          [{ "url" => other_url, "valueReference" => { "reference" => "Condition/c1" } }]
        )

        get "/Composition", params: { patient: patient_id, "problem:missing" => "true" }
        expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([unlinked_id])

        get "/Composition", params: { patient: patient_id, "problem:missing" => "false" }
        expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([linked_id])
      end

      it "chains into the Condition (problem.code)" do
        patient_id = create_patient
        post "/Condition", params: valid_condition_payload(subject_id: patient_id), as: :json
        condition_id = JSON.parse(response.body)["id"]
        target_id = create_with_extension(patient_id, problem_extension(condition_id))
        create_with_extension(patient_id, problem_extension("c2"))

        get "/Composition", params: { "problem.code" => "J20.9" }

        expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([target_id])
      end
    end
  end

  it "joins the patient compartment ($everything)" do
    patient_id = create_patient
    post "/Composition", params: valid_composition_payload(subject_id: patient_id), as: :json

    get "/Patient/#{patient_id}/$everything"

    types = JSON.parse(response.body)["entry"].map { |e| e.dig("resource", "resourceType") }
    expect(types).to contain_exactly("Patient", "Composition")
  end
end
