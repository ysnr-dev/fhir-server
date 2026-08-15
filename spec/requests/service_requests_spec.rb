require "rails_helper"

RSpec.describe "ServiceRequests", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /ServiceRequest" do
    it "creates and returns 201 with Location, ETag, and meta" do
      subject_id = create_patient

      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/ServiceRequest/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("ServiceRequest")
      expect(body["meta"]["versionId"]).to eq("1")
    end

    it "does not require identifier" do
      subject_id = create_patient

      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json

      expect(response).to have_http_status(:created)
    end

    it "returns 422 when status is missing" do
      subject_id = create_patient

      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id).except("status"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for an invalid intent" do
      subject_id = create_patient

      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id, intent: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when subject references a non-existent patient" do
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 400 when resourceType does not match" do
      subject_id = create_patient

      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id).merge("resourceType" => "Patient"), as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 for malformed JSON" do
      post "/ServiceRequest", params: "{not valid json", headers: { "CONTENT_TYPE" => "application/fhir+json" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /ServiceRequest/:id" do
    it "returns the resource" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      get "/ServiceRequest/#{id}"

      expect(response).to have_http_status(:ok)
      expect(response.headers["ETag"]).to eq('W/"1"')
    end

    it "returns 404 for an unknown id" do
      get "/ServiceRequest/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end

    it "returns 410 for a deleted resource" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      delete "/ServiceRequest/#{id}"

      get "/ServiceRequest/#{id}"

      expect(response).to have_http_status(:gone)
    end
  end

  describe "PUT /ServiceRequest/:id" do
    it "updates the resource and increments the version" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/ServiceRequest/#{id}", params: valid_service_request_payload(subject_id: subject_id, status: "completed"), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("completed")
      expect(body["meta"]["versionId"]).to eq("2")
    end

    it "returns 412 when If-Match does not match the current version" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      put "/ServiceRequest/#{id}", params: valid_service_request_payload(subject_id: subject_id),
                                   headers: { "If-Match" => 'W/"99"' }, as: :json

      expect(response).to have_http_status(:precondition_failed)
    end
  end

  describe "DELETE /ServiceRequest/:id" do
    it "deletes the resource and returns 204" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]

      delete "/ServiceRequest/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/ServiceRequest/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "history and vread" do
    it "returns full version history and a specific version" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      put "/ServiceRequest/#{id}", params: valid_service_request_payload(subject_id: subject_id, status: "completed"), as: :json

      get "/ServiceRequest/#{id}/_history"
      history = JSON.parse(response.body)
      expect(history["type"]).to eq("history")
      expect(history["total"]).to eq(2)

      get "/ServiceRequest/#{id}/_history/1"
      expect(JSON.parse(response.body)["status"]).to eq("active")
    end
  end

  describe "GET /ServiceRequest (search)" do
    it "finds by subject reference" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json

      get "/ServiceRequest", params: { subject: "Patient/#{subject_id}" }

      expect(response).to have_http_status(:ok)
      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by status" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id, status: "completed"), as: :json

      get "/ServiceRequest", params: { status: "completed" }

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to be >= 1
    end

    it "excludes deleted resources from search results" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      id = JSON.parse(response.body)["id"]
      delete "/ServiceRequest/#{id}"

      get "/ServiceRequest", params: { _id: id }

      expect(JSON.parse(response.body)["total"]).to eq(0)
    end

    # 部門ワークリストは「その日の放射線検査だけ」を引くために category で絞る。
    # 1 件のオーダーが種別(rad)と入外区分(outpatient)のように複数の概念を並べるので、
    # 先頭以外の concept でも引けることまで見る。
    describe "category" do
      let(:order_type_system) { "http://fhir-client.local/CodeSystem/order-type" }
      let(:setting_system) { "http://fhir-client.local/CodeSystem/encounter-setting" }

      def create_categorized(subject_id, type_code)
        post "/ServiceRequest",
             params: valid_service_request_payload(
               subject_id: subject_id,
               category: [
                 { "coding" => [{ "system" => order_type_system, "code" => type_code }] },
                 { "coding" => [{ "system" => setting_system, "code" => "outpatient" }] }
               ]
             ),
             as: :json
        JSON.parse(response.body)["id"]
      end

      it "finds by system|code and leaves other order types out" do
        subject_id = create_patient
        rad_id = create_categorized(subject_id, "rad")
        create_categorized(subject_id, "lab")

        get "/ServiceRequest", params: { category: "#{order_type_system}|rad" }

        bundle = JSON.parse(response.body)
        expect(bundle["total"]).to eq(1)
        expect(bundle["entry"].first["resource"]["id"]).to eq(rad_id)
      end

      it "matches a concept that is not the first one" do
        subject_id = create_patient
        rad_id = create_categorized(subject_id, "rad")

        get "/ServiceRequest", params: { category: "#{setting_system}|outpatient" }

        bundle = JSON.parse(response.body)
        expect(bundle["entry"].map { |e| e["resource"]["id"] }).to include(rad_id)
      end

      it "supports category:missing" do
        subject_id = create_patient
        create_categorized(subject_id, "rad")
        post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
        uncategorized_id = JSON.parse(response.body)["id"]

        get "/ServiceRequest", params: { subject: "Patient/#{subject_id}", "category:missing" => "true" }

        bundle = JSON.parse(response.body)
        expect(bundle["entry"].map { |e| e["resource"]["id"] }).to eq([uncategorized_id])
      end
    end

    # 依頼の理由(対象の病名)。カルテを 1 つのプロブレムで縦に読むための絞り込み。
    describe "reason-reference" do
      def create_with_reason(subject_id, condition_ref, **overrides)
        post "/ServiceRequest",
             params: valid_service_request_payload(
               subject_id: subject_id,
               reasonReference: [{ "reference" => condition_ref }],
               **overrides
             ),
             as: :json
        expect(response).to have_http_status(:created)
        JSON.parse(response.body)["id"]
      end

      it "finds the orders placed for one problem" do
        subject_id = create_patient
        target_id = create_with_reason(subject_id, "Condition/c1")
        create_with_reason(subject_id, "Condition/c2")
        post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json

        get "/ServiceRequest", params: { "reason-reference" => "Condition/c1" }

        expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([target_id])
      end

      it "qualifies a bare id as a Condition" do
        subject_id = create_patient
        target_id = create_with_reason(subject_id, "Condition/c1")

        get "/ServiceRequest", params: { "reason-reference" => "c1" }

        expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([target_id])
      end

      # 明細のオーダーも親から引き継いだ理由を持つので、ヘッダだけを引くには
      # based-on:missing=true を併用する。
      it "narrows to the header order with based-on:missing" do
        subject_id = create_patient
        header_id = create_with_reason(subject_id, "Condition/c1")
        create_with_reason(subject_id, "Condition/c1", basedOn: [{ "reference" => "ServiceRequest/#{header_id}" }])

        get "/ServiceRequest", params: { "reason-reference" => "Condition/c1" }
        expect(JSON.parse(response.body)["total"]).to eq(2)

        get "/ServiceRequest",
            params: { "reason-reference" => "Condition/c1", "based-on:missing" => "true" }
        expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to eq([header_id])
      end

      it "includes the referenced Condition with _include" do
        subject_id = create_patient
        post "/Condition", params: valid_condition_payload(subject_id: subject_id), as: :json
        condition_id = JSON.parse(response.body)["id"]
        create_with_reason(subject_id, "Condition/#{condition_id}")

        get "/ServiceRequest", params: { "_include" => "ServiceRequest:reason-reference" }

        included = JSON.parse(response.body)["entry"].select { |e| e.dig("search", "mode") == "include" }
        expect(included.map { |e| e.dig("resource", "id") }).to eq([condition_id])
      end
    end

    describe "_revinclude=MedicationRequest:based-on" do
      it "includes MedicationRequests that reference the matched ServiceRequest" do
        subject_id = create_patient
        post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
        service_request_id = JSON.parse(response.body)["id"]
        post "/MedicationRequest",
             params: valid_medication_request_payload(
               subject_id: subject_id,
               basedOn: [{ "reference" => "ServiceRequest/#{service_request_id}" }]
             ),
             as: :json
        medication_request_id = JSON.parse(response.body)["id"]

        get "/ServiceRequest", params: { _id: service_request_id, _revinclude: "MedicationRequest:based-on" }

        bundle = JSON.parse(response.body)
        expect(bundle["total"]).to eq(1)

        modes = bundle["entry"].group_by { |entry| entry.dig("search", "mode") }
        expect(modes["match"].map { |entry| entry["resource"]["id"] }).to eq([service_request_id])

        included = modes["include"]
        expect(included.size).to eq(1)
        expect(included.first["resource"]["resourceType"]).to eq("MedicationRequest")
        expect(included.first["resource"]["id"]).to eq(medication_request_id)
        expect(included.first["fullUrl"]).to end_with("/MedicationRequest/#{medication_request_id}")
      end

      it "returns only the match when no MedicationRequest references it" do
        subject_id = create_patient
        post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
        service_request_id = JSON.parse(response.body)["id"]

        get "/ServiceRequest", params: { _id: service_request_id, _revinclude: "MedicationRequest:based-on" }

        bundle = JSON.parse(response.body)
        expect(bundle["total"]).to eq(1)
        expect(bundle["entry"].map { |entry| entry.dig("search", "mode") }).to eq(["match"])
      end
    end

    # ServiceRequest 同士の親子(オーダーのヘッダ → 明細 → パネルの構成項目)。
    describe "based-on (ServiceRequest の親子)" do
      # 親・子・孫を 1 件ずつ作る。
      def create_hierarchy(subject_id)
        post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
        parent_id = JSON.parse(response.body)["id"]
        post "/ServiceRequest",
             params: valid_service_request_payload(
               subject_id: subject_id, basedOn: [{ "reference" => "ServiceRequest/#{parent_id}" }]
             ),
             as: :json
        child_id = JSON.parse(response.body)["id"]
        post "/ServiceRequest",
             params: valid_service_request_payload(
               subject_id: subject_id, basedOn: [{ "reference" => "ServiceRequest/#{child_id}" }]
             ),
             as: :json
        [parent_id, child_id, JSON.parse(response.body)["id"]]
      end

      def entry_ids(mode)
        JSON.parse(response.body)["entry"].to_a
            .select { |entry| entry.dig("search", "mode") == mode }
            .map { |entry| entry.dig("resource", "id") }
      end

      it "finds the children of a ServiceRequest" do
        subject_id = create_patient
        parent_id, child_id, = create_hierarchy(subject_id)

        get "/ServiceRequest", params: { "based-on" => "ServiceRequest/#{parent_id}" }

        expect(JSON.parse(response.body)["total"]).to eq(1)
        expect(entry_ids("match")).to eq([child_id])
      end

      # オーダー一覧はヘッダだけを並べたいので、明細を落とせる必要がある。
      it "returns only the top-level requests with based-on:missing=true" do
        subject_id = create_patient
        parent_id, = create_hierarchy(subject_id)

        get "/ServiceRequest", params: { subject: "Patient/#{subject_id}", "based-on:missing" => "true" }

        expect(entry_ids("match")).to eq([parent_id])
      end

      it "includes the children with _revinclude=ServiceRequest:based-on" do
        subject_id = create_patient
        parent_id, child_id, = create_hierarchy(subject_id)

        get "/ServiceRequest", params: { _id: parent_id, _revinclude: "ServiceRequest:based-on" }

        expect(entry_ids("match")).to eq([parent_id])
        expect(entry_ids("include")).to eq([child_id])
      end

      # パネル検査の構成項目まで(ヘッダ → パネル → 構成項目)を 1 リクエストで取る。
      it "includes grandchildren with _revinclude:iterate" do
        subject_id = create_patient
        parent_id, child_id, grandchild_id = create_hierarchy(subject_id)

        get "/ServiceRequest",
            params: { _id: parent_id, "_revinclude:iterate" => "ServiceRequest:based-on" }

        expect(entry_ids("match")).to eq([parent_id])
        expect(entry_ids("include")).to contain_exactly(child_id, grandchild_id)
      end

      it "resolves the parent with _include=ServiceRequest:based-on" do
        subject_id = create_patient
        parent_id, child_id, = create_hierarchy(subject_id)

        get "/ServiceRequest", params: { _id: child_id, _include: "ServiceRequest:based-on" }

        expect(entry_ids("match")).to eq([child_id])
        expect(entry_ids("include")).to eq([parent_id])
      end
    end

    it "ignores an unsupported _revinclude value" do
      subject_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: subject_id), as: :json
      service_request_id = JSON.parse(response.body)["id"]

      get "/ServiceRequest", params: { _id: service_request_id, _revinclude: "Foo:bar" }

      expect(response).to have_http_status(:ok)
      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(1)
      expect(bundle["entry"].map { |entry| entry.dig("search", "mode") }).to eq(["match"])
    end
  end
end
