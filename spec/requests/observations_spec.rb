require "rails_helper"

RSpec.describe "Observations", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /Observation" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/Observation/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("Observation")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_Observation_Common"])
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/Observation", params: valid_observation_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for an invalid status" do
      subject_id = create_patient

      post "/Observation", params: valid_observation_payload(subject_id: subject_id, status: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when code is missing" do
      subject_id = create_patient

      post "/Observation", params: valid_observation_payload(subject_id: subject_id).except("code"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/Observation", params: valid_observation_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 400 when resourceType does not match" do
      subject_id = create_patient

      post "/Observation", params: valid_observation_payload(subject_id: subject_id).merge("resourceType" => "Patient"), as: :json

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /Observation/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Observation/#{id}"

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).to eq('W/"1"')
    end

    it "returns 404 for an unknown id" do
      get "/Observation/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/Observation/#{id}", params: valid_observation_payload(subject_id: subject_id, status: "amended"), as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("amended")
      expect(body["meta"]["versionId"]).to eq("2")

      delete "/Observation/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/Observation/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /Observation (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { subject: "Patient/#{subject_id}" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by code" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { code: "718-7" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    it "finds by category" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { category: "laboratory" }

      expect(JSON.parse(response.body)["total"]).to be >= 1
    end

    # 実施記録に伴って測った値(放射線検査の被曝線量)。
    it "finds by part-of (the procedure it was measured during)" do
      subject_id = create_patient
      post "/Procedure", params: valid_procedure_payload(subject_id: subject_id), as: :json
      procedure_id = JSON.parse(response.body)["id"]
      post "/Observation",
           params: valid_observation_payload(
             subject_id: subject_id, partOf: [{ "reference" => "Procedure/#{procedure_id}" }]
           ),
           as: :json
      # 同じ患者の、実施に紐づかない検査値。part-of で拾われないことを確かめる。
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { "part-of" => "Procedure/#{procedure_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # テンプレート回答から抽出した値。回答を編集・削除する側が「前回この回答から
    # 作った Observation」を引き直すのに使う。
    it "finds by derived-from (the answer it was extracted from)" do
      subject_id = create_patient
      post "/Observation",
           params: valid_observation_payload(
             subject_id: subject_id, derivedFrom: [{ "reference" => "QuestionnaireResponse/qr1" }]
           ),
           as: :json
      derived_id = JSON.parse(response.body)["id"]
      # 別の回答から作った値と、抽出でない値。どちらも拾われないことを確かめる。
      post "/Observation",
           params: valid_observation_payload(
             subject_id: subject_id, derivedFrom: [{ "reference" => "QuestionnaireResponse/qr2" }]
           ),
           as: :json
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { "derived-from" => "QuestionnaireResponse/qr1" }

      expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([derived_id])
    end

    # 測定の元になった依頼・計画。看護指示の観察項目は指示を、パスの評価は計画を指す。
    describe "based-on" do
      def create_order(subject_id)
        post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
        JSON.parse(response.body)["id"]
      end

      def create_care_plan(subject_id, **overrides)
        post "/CarePlan", params: valid_care_plan_payload(subject_id: subject_id, **overrides), as: :json
        expect(response).to have_http_status(:created)
        JSON.parse(response.body)["id"]
      end

      def create_observation(subject_id, based_on)
        post "/Observation",
             params: valid_observation_payload(subject_id: subject_id, basedOn: based_on.map { |r| { "reference" => r } }),
             as: :json
        expect(response).to have_http_status(:created)
        JSON.parse(response.body)["id"]
      end

      it "finds by based-on for an order and for a care plan" do
        subject_id = create_patient
        order_id = create_order(subject_id)
        other_order_id = create_order(subject_id)
        plan_id = create_care_plan(subject_id)
        by_order = create_observation(subject_id, ["ServiceRequest/#{order_id}"])
        by_plan = create_observation(subject_id, ["CarePlan/#{plan_id}"])
        create_observation(subject_id, ["ServiceRequest/#{other_order_id}"])
        post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

        get "/Observation", params: { "based-on" => "ServiceRequest/#{order_id}" }
        expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([by_order])

        # 型を省いた id は依頼とみなす。
        get "/Observation", params: { "based-on" => order_id }
        expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([by_order])

        get "/Observation", params: { "based-on" => "CarePlan/#{plan_id},ServiceRequest/#{order_id}" }
        expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to match_array([by_order, by_plan])
      end

      it "adds the observations of an order with _revinclude=Observation:based-on" do
        subject_id = create_patient
        order_id = create_order(subject_id)
        other_order_id = create_order(subject_id)
        observation_id = create_observation(subject_id, ["ServiceRequest/#{order_id}"])
        create_observation(subject_id, ["ServiceRequest/#{other_order_id}"])

        get "/ServiceRequest", params: { _id: order_id, "_revinclude" => "Observation:based-on" }

        included = JSON.parse(response.body)["entry"].select { |e| e.dig("search", "mode") == "include" }
        expect(included.map { |e| [e["resource"]["resourceType"], e["resource"]["id"]] })
          .to eq([["Observation", observation_id]])
      end

      it "adds the evaluated care plan and its ancestors with _include=Observation:based-on" do
        subject_id = create_patient
        root_id = create_care_plan(subject_id)
        unit_id = create_care_plan(subject_id, partOf: [{ "reference" => "CarePlan/#{root_id}" }])
        observation_id = create_observation(subject_id, ["CarePlan/#{unit_id}"])

        get "/Observation?_id=#{observation_id}&_include=Observation:based-on&_include:iterate=CarePlan:part-of"

        included = JSON.parse(response.body)["entry"].select { |e| e.dig("search", "mode") == "include" }
        expect(included.map { |e| e["resource"]["id"] }).to match_array([unit_id, root_id])
      end
    end

    # バイタルなど、対象プロブレムを持つ測定値の絞り込み。Composition:problem と同じ
    # ローカル拡張の読み方(url も一致条件に入れる)。
    describe "problem" do
      let(:problem_url) { "http://fhir-client.local/StructureDefinition/observation-problem" }
      let(:other_url) { "http://fhir-client.local/StructureDefinition/some-other-reference" }

      def create_with_extension(subject_id, extension)
        post "/Observation",
             params: valid_observation_payload(subject_id: subject_id).merge("extension" => extension),
             as: :json
        expect(response).to have_http_status(:created)
        JSON.parse(response.body)["id"]
      end

      it "finds the measurements recorded against one problem" do
        subject_id = create_patient
        target_id = create_with_extension(
          subject_id,
          [{ "url" => problem_url, "valueReference" => { "reference" => "Condition/c1" } }]
        )
        create_with_extension(
          subject_id,
          [{ "url" => problem_url, "valueReference" => { "reference" => "Condition/c2" } }]
        )
        # 同じ参照を持つ別の拡張は拾わない。
        create_with_extension(
          subject_id,
          [{ "url" => other_url, "valueReference" => { "reference" => "Condition/c1" } }]
        )

        get "/Observation", params: { problem: "Condition/c1" }

        expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([target_id])
      end
    end

    it "finds by date (effective time)" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json

      get "/Observation", params: { date: "ge2026-07-19", subject: "Patient/#{subject_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "excludes deleted resources from search results" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      delete "/Observation/#{id}"

      get "/Observation", params: { _id: id }

      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    it "includes the referenced Patient via Observation:subject" do
      subject_id = create_patient
      post "/Observation", params: valid_observation_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/Observation", params: { _id: id, _include: "Observation:subject" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
      expect(included.first["resource"]["id"]).to eq(subject_id)
    end
  end
end
