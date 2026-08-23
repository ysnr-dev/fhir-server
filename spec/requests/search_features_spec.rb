require "rails_helper"

RSpec.describe "Search features (chaining, _has, _summary/_elements, _total)", type: :request do
  def create_patient(overrides = {})
    post "/Patient", params: valid_patient_payload(overrides), as: :json
    JSON.parse(response.body)["id"]
  end

  def create_observation(patient_id, overrides = {})
    post "/Observation", params: valid_observation_payload(subject_id: patient_id, **overrides), as: :json
    JSON.parse(response.body)["id"]
  end

  describe "chained search" do
    it "finds observations through the subject's name (UTF-8, typed and untyped)" do
      yamada = create_patient
      sato = create_patient("name" => [{ "use" => "official", "family" => "佐藤", "given" => ["次郎"] }])
      target = create_observation(yamada)
      create_observation(sato)

      get "/Observation?subject:Patient.family=#{Rack::Utils.escape('山田')}"
      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(1)
      expect(bundle["entry"].first.dig("resource", "id")).to eq(target)

      get "/Observation?subject.family=#{Rack::Utils.escape('佐藤')}"
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "keeps chained params intact in paging links" do
      patient_id = create_patient
      3.times { create_observation(patient_id) }

      get "/Observation?subject:Patient.family=#{Rack::Utils.escape('山田')}&_count=2"

      bundle = JSON.parse(response.body)
      next_link = bundle["link"].find { |l| l["relation"] == "next" }
      expect(next_link["url"]).to include("subject:Patient.family=", "_offset=2")

      get URI.parse(next_link["url"]).request_uri
      expect(JSON.parse(response.body)["entry"].size).to eq(1)
    end
  end

  describe "_include:iterate" do
    it "includes resources referenced by included resources" do
      patient_id = create_patient
      post "/Encounter", params: valid_encounter_payload("subject" => { "reference" => "Patient/#{patient_id}" }), as: :json
      encounter_id = JSON.parse(response.body)["id"]
      post "/MedicationRequest",
           params: valid_medication_request_payload(subject_id: patient_id,
                                                    encounter: { "reference" => "Encounter/#{encounter_id}" }),
           as: :json

      get "/MedicationRequest?_include=MedicationRequest:encounter&_include:iterate=Encounter:subject"

      bundle = JSON.parse(response.body)
      modes = bundle["entry"].group_by { |e| e.dig("search", "mode") }
      included_types = modes["include"].map { |e| e.dig("resource", "resourceType") }
      expect(included_types).to contain_exactly("Encounter", "Patient")

      self_link = bundle["link"].find { |l| l["relation"] == "self" }
      expect(self_link["url"]).to include("_include:iterate=Encounter%3Asubject")
    end
  end

  describe "_has (reverse chaining)" do
    it "finds patients that have a matching observation" do
      with_obs = create_patient
      create_patient
      create_observation(with_obs)

      get "/Patient?_has:Observation:patient:code=718-7"

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(1)
      expect(bundle["entry"].first.dig("resource", "id")).to eq(with_obs)
    end
  end

  # fhir-client の populate 系フックが「_count=1 + _sort + _include/_revinclude で
  # 最新1件とその関連リソースを1リクエストで取る」形に依存するため、ソート・
  # ページング後の match に対してのみ include が解決されることを固定する。
  describe "_sort combined with _include / _revinclude and _count" do
    it "includes only the resources referenced by the sorted, paged matches (_include)" do
      patient_id = create_patient
      older_obs = create_observation(patient_id)
      newer_obs = create_observation(patient_id)

      post "/DiagnosticReport",
           params: valid_diagnostic_report_payload(
             subject_id: patient_id,
             "effectiveDateTime" => "2026-07-01T10:00:00+09:00",
             "result" => [{ "reference" => "Observation/#{older_obs}" }]
           ), as: :json
      post "/DiagnosticReport",
           params: valid_diagnostic_report_payload(
             subject_id: patient_id,
             "effectiveDateTime" => "2026-07-20T10:00:00+09:00",
             "result" => [{ "reference" => "Observation/#{newer_obs}" }]
           ), as: :json
      newest_report = JSON.parse(response.body)["id"]

      get "/DiagnosticReport?patient=#{patient_id}&_sort=-date&_count=1&_include=DiagnosticReport:result"

      bundle = JSON.parse(response.body)
      modes = bundle["entry"].group_by { |e| e.dig("search", "mode") }
      expect(modes["match"].map { |e| e.dig("resource", "id") }).to eq([newest_report])
      expect(modes["include"].map { |e| e.dig("resource", "id") }).to eq([newer_obs])
    end

    it "revincludes only the resources referencing the sorted, paged matches (_revinclude)" do
      patient_id = create_patient

      post "/ServiceRequest",
           params: valid_service_request_payload(subject_id: patient_id, "authoredOn" => "2026-07-01T10:00:00+09:00"),
           as: :json
      older_sr = JSON.parse(response.body)["id"]
      post "/ServiceRequest",
           params: valid_service_request_payload(subject_id: patient_id, "authoredOn" => "2026-07-20T10:00:00+09:00"),
           as: :json
      newer_sr = JSON.parse(response.body)["id"]

      post "/MedicationRequest",
           params: valid_medication_request_payload(subject_id: patient_id,
                                                    basedOn: [{ "reference" => "ServiceRequest/#{older_sr}" }]),
           as: :json
      post "/MedicationRequest",
           params: valid_medication_request_payload(subject_id: patient_id,
                                                    basedOn: [{ "reference" => "ServiceRequest/#{newer_sr}" }]),
           as: :json
      newer_mr = JSON.parse(response.body)["id"]

      get "/ServiceRequest?patient=#{patient_id}&_sort=-authoredon&_count=1&_revinclude=MedicationRequest:based-on"

      bundle = JSON.parse(response.body)
      modes = bundle["entry"].group_by { |e| e.dig("search", "mode") }
      expect(modes["match"].map { |e| e.dig("resource", "id") }).to eq([newer_sr])
      expect(modes["include"].map { |e| e.dig("resource", "id") }).to eq([newer_mr])
    end
  end

  describe "_summary=count" do
    it "returns total and links but no entry element" do
      2.times { create_patient }

      get "/Patient?_summary=count"

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(2)
      expect(bundle).not_to have_key("entry")
      expect(bundle["link"].first["url"]).to include("_summary=count")
    end
  end

  describe "_elements" do
    it "returns only the requested elements plus mandatory keys, tagged SUBSETTED" do
      create_patient

      get "/Patient?_elements=name"

      resource = JSON.parse(response.body)["entry"].first["resource"]
      expect(resource.keys).to contain_exactly("resourceType", "id", "meta", "name")
      expect(resource["meta"]["tag"]).to include(
        "system" => "http://terminology.hl7.org/CodeSystem/v3-ObservationValue", "code" => "SUBSETTED"
      )
    end
  end

  describe "_summary=text" do
    it "keeps only the narrative alongside the mandatory keys" do
      post "/Patient", params: valid_patient_payload("text" => { "status" => "generated", "div" => "<div>山田太郎</div>" }),
                       as: :json

      get "/Patient?_summary=text"

      resource = JSON.parse(response.body)["entry"].first["resource"]
      expect(resource.keys).to contain_exactly("resourceType", "id", "meta", "text")
    end
  end

  describe "_total=none" do
    it "omits total but still pages with a next link on a full page" do
      2.times { create_patient }

      get "/Patient?_total=none&_count=2"

      bundle = JSON.parse(response.body)
      expect(bundle).not_to have_key("total")
      expect(bundle["entry"].size).to eq(2)
      next_link = bundle["link"].find { |l| l["relation"] == "next" }
      expect(next_link["url"]).to include("_total=none", "_offset=2")

      get URI.parse(next_link["url"]).request_uri
      final = JSON.parse(response.body)
      expect(final["entry"]).to eq([])
      expect(final["link"].find { |l| l["relation"] == "next" }).to be_nil
    end
  end

  describe ":missing modifier" do
    it "filters on element absence end-to-end" do
      create_patient
      post "/Patient", params: valid_patient_payload.except("gender"), as: :json

      get "/Patient?gender:missing=true"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Patient?gender:missing=false"
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end
  end

  describe "date prefixes" do
    it "honors sa/eb on birthdate" do
      create_patient("birthDate" => "1990-06-15")

      get "/Patient?birthdate=sa1990-01-01"
      expect(JSON.parse(response.body)["total"]).to eq(1)

      get "/Patient?birthdate=eb1990-01-01"
      expect(JSON.parse(response.body)["total"]).to eq(0)
    end
  end


  describe ":not modifier on token search" do
    it "excludes the value on a column-backed token (comma = none of them)" do
      patient_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: patient_id), as: :json
      active_id = JSON.parse(response.body)["id"]
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: patient_id, status: "completed"), as: :json
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: patient_id, status: "revoked"), as: :json

      get "/ServiceRequest?subject=Patient/#{patient_id}&status:not=completed,revoked"

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(1)
      expect(bundle["entry"].first["resource"]["id"]).to eq(active_id)
    end

    it "excludes token-row matches, keeping resources without any value" do
      order_type_system = "http://fhir-client.local/CodeSystem/order-type"
      patient_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(
        subject_id: patient_id,
        category: [{ "coding" => [{ "system" => order_type_system, "code" => "lab" }] }]
      ), as: :json
      post "/ServiceRequest", params: valid_service_request_payload(
        subject_id: patient_id,
        category: [{ "coding" => [{ "system" => order_type_system, "code" => "rad" }] }]
      ), as: :json
      rad_id = JSON.parse(response.body)["id"]
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: patient_id), as: :json
      uncategorized_id = JSON.parse(response.body)["id"]

      get "/ServiceRequest?subject=Patient/#{patient_id}&category:not=#{Rack::Utils.escape("#{order_type_system}|lab")}"

      bundle = JSON.parse(response.body)
      expect(bundle["entry"].map { |e| e["resource"]["id"] }).to contain_exactly(rad_id, uncategorized_id)
    end

    it "excludes an id with _id:not" do
      first = create_patient
      second = create_patient

      get "/Patient?_id:not=#{first}"

      ids = JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }
      expect(ids).to include(second)
      expect(ids).not_to include(first)
    end

    it "is rejected on non-token params (lenient skip)" do
      patient_id = create_patient

      get "/Patient?birthdate:not=1990-01-01"

      # date に :not は未対応。lenient では無視され全件が返る(strict では 400)。
      expect(JSON.parse(response.body)["entry"].map { |e| e["resource"]["id"] }).to include(patient_id)
    end
  end

  describe "Prefer: handling=strict" do
    it "rejects an unknown parameter with 400 + OperationOutcome naming it" do
      get "/Patient?bogus=1", headers: { "Prefer" => "handling=strict" }

      expect(response).to have_http_status(:bad_request)
      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("OperationOutcome")
      expect(body["issue"].first["code"]).to eq("not-supported")
      expect(body["issue"].first["diagnostics"]).to include("bogus")
    end

    it "rejects an unsupported modifier and reports every problem at once" do
      get "/Patient?birthdate:contains=1990&bogus=1", headers: { "Prefer" => "handling=strict" }

      expect(response).to have_http_status(:bad_request)
      diagnostics = JSON.parse(response.body)["issue"].map { |i| i["diagnostics"] }.join("\n")
      expect(diagnostics).to include("birthdate")
      expect(diagnostics).to include("bogus")
    end

    it "rejects unknown _include / _revinclude tokens and _sort keys" do
      get "/Patient?_include=Patient:bogus", headers: { "Prefer" => "handling=strict" }
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["issue"].first["diagnostics"]).to include("Patient:bogus")

      get "/Patient?_revinclude=Bogus:subject", headers: { "Prefer" => "handling=strict" }
      expect(response).to have_http_status(:bad_request)

      get "/Patient?_sort=bogus", headers: { "Prefer" => "handling=strict" }
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["issue"].first["diagnostics"]).to include("bogus")
    end

    it "accepts a fully supported search, alongside other preferences" do
      patient_id = create_patient
      create_observation(patient_id)

      get "/Observation?subject=Patient/#{patient_id}&_include=Observation:subject&_sort=-_lastUpdated",
          headers: { "Prefer" => "return=minimal, handling=strict" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "stays lenient without the header (unknown params are ignored)" do
      create_patient

      get "/Patient?bogus=1"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["total"]).to be >= 1
    end
  end

  # ワークリストの進捗フィルタ。オーダー(ServiceRequest)側から、進捗を持つ別リソース
  # (Task)の status で絞る。綴りを回帰 spec で固定して防御する。
  describe "_has:Task:focus:status" do
    it "finds orders whose Task has the given status" do
      patient_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: patient_id), as: :json
      in_progress_order = JSON.parse(response.body)["id"]
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: patient_id), as: :json
      completed_order = JSON.parse(response.body)["id"]
      post "/Task", params: valid_task_payload(for_id: patient_id, service_request_id: in_progress_order), as: :json
      post "/Task", params: valid_task_payload(for_id: patient_id, service_request_id: completed_order, status: "completed"), as: :json

      get "/ServiceRequest?subject=Patient/#{patient_id}&_has:Task:focus:status=in-progress"

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(1)
      expect(bundle["entry"].first["resource"]["id"]).to eq(in_progress_order)
    end

    it "combines with business-status" do
      patient_id = create_patient
      post "/ServiceRequest", params: valid_service_request_payload(subject_id: patient_id), as: :json
      order_id = JSON.parse(response.body)["id"]
      post "/Task", params: valid_task_payload(for_id: patient_id, service_request_id: order_id), as: :json

      get "/ServiceRequest?subject=Patient/#{patient_id}&_has:Task:focus:business-status=collected"

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end
  end


  # 病棟(ward) > 病室(room) > ベッド(bed)の 3 階層。入院(Encounter.location = bed)を
  # 病棟でサーバー側から絞るための多段チェーン。
  describe "multi-level chained search (location.partof.partof)" do
    def create_location(name, partof_id: nil)
      overrides = { "name" => name }
      overrides["partOf"] = { "reference" => "Location/#{partof_id}" } if partof_id
      post "/Location", params: valid_location_payload(overrides), as: :json
      JSON.parse(response.body)["id"]
    end

    def create_admission(patient_id, bed_id)
      post "/Encounter", params: valid_encounter_payload(
        "status" => "in-progress",
        "class" => { "system" => "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code" => "IMP" },
        "subject" => { "reference" => "Patient/#{patient_id}" },
        "location" => [{ "location" => { "reference" => "Location/#{bed_id}" } }],
        "period" => { "start" => "2026-08-20T10:00:00+09:00" }
      ), as: :json
      JSON.parse(response.body)["id"]
    end

    it "filters encounters by ward through bed -> room -> ward" do
      ward = create_location("東3階病棟")
      room = create_location("301号室", partof_id: ward)
      bed = create_location("1", partof_id: room)
      other_ward = create_location("西2階病棟")
      other_room = create_location("201号室", partof_id: other_ward)
      other_bed = create_location("1", partof_id: other_room)

      patient_id = create_patient
      target = create_admission(patient_id, bed)
      create_admission(create_patient, other_bed)

      get "/Encounter?status=in-progress&location.partof.partof=Location/#{ward}"

      bundle = JSON.parse(response.body)
      expect(bundle["total"]).to eq(1)
      expect(bundle["entry"].first["resource"]["id"]).to eq(target)

      # 2 段(病室)でも引ける。
      get "/Encounter?status=in-progress&location.partof=Location/#{room}"
      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "rejects chains deeper than 3 hops (strict) and skips them leniently" do
      get "/Encounter?location.partof.partof.partof=Location/x",
          headers: { "Prefer" => "handling=strict" }
      expect(response).to have_http_status(:bad_request)

      get "/Encounter?location.partof.partof.partof=Location/x"
      expect(response).to have_http_status(:ok)
    end
  end

  # ベッドの読み出しに _include:iterate を重ねると、病室(1 段目)だけでなく
  # 病棟(2 段目)まで同じ応答に含まれる。患者ヘッダの入院場所の表示が依存する。
  describe "_include:iterate over Location.partof (bed -> room -> ward)" do
    it "includes both the room and the ward" do
      post "/Location", params: valid_location_payload("name" => "病棟"), as: :json
      ward = JSON.parse(response.body)["id"]
      post "/Location", params: valid_location_payload("name" => "病室", "partOf" => { "reference" => "Location/#{ward}" }), as: :json
      room = JSON.parse(response.body)["id"]
      post "/Location", params: valid_location_payload("name" => "ベッド", "partOf" => { "reference" => "Location/#{room}" }), as: :json
      bed = JSON.parse(response.body)["id"]

      get "/Location?_id=#{bed}&_include=Location:partof&_include:iterate=Location:partof"

      bundle = JSON.parse(response.body)
      ids = bundle["entry"].map { |e| e["resource"]["id"] }
      expect(ids).to contain_exactly(bed, room, ward)
    end
  end

  # テンプレート回答からの派生 Observation の一括参照。複数の回答を保存する前に
  # 1 検索で「前回生成した Observation」を集められる(N+1 の解消)。
  describe "reference search with comma-OR (derived-from)" do
    it "finds observations derived from any of the listed responses" do
      patient_id = create_patient
      qr_a = "QuestionnaireResponse/qr-a"
      qr_b = "QuestionnaireResponse/qr-b"
      obs_a = create_observation(patient_id, "derivedFrom" => [{ "reference" => qr_a }])
      obs_b = create_observation(patient_id, "derivedFrom" => [{ "reference" => qr_b }])
      create_observation(patient_id) # 派生ではない測定

      get "/Observation?derived-from=#{qr_a},#{qr_b}"

      bundle = JSON.parse(response.body)
      expect(bundle["entry"].map { |e| e["resource"]["id"] }).to contain_exactly(obs_a, obs_b)
    end
  end
end
