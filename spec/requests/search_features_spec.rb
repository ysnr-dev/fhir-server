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
end
