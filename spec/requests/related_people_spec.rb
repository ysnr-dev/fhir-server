require "rails_helper"

RSpec.describe "RelatedPeople", type: :request do
  def create_patient
    post "/Patient", params: valid_patient_payload, as: :json
    JSON.parse(response.body)["id"]
  end

  def create_related_person(patient_id:, **args)
    post "/RelatedPerson", params: valid_related_person_payload(patient_id: patient_id, **args), as: :json
    JSON.parse(response.body)["id"]
  end

  describe "POST /RelatedPerson" do
    it "creates and returns 201 with Location, ETag, and meta" do
      patient_id = create_patient

      post "/RelatedPerson", params: valid_related_person_payload(patient_id: patient_id), as: :json

      expect(response).to have_http_status(:created)
      expect(response.content_type).to include("application/fhir+json")
      expect(response.headers["Location"]).to match(%r{/RelatedPerson/[\w-]+/_history/1\z})
      expect(response.headers["ETag"]).to eq('W/"1"')

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("RelatedPerson")
      expect(body["meta"]["profile"]).to eq(["http://jpfhir.jp/fhir/core/StructureDefinition/JP_RelatedPerson"])
    end

    it "returns 422 without a patient" do
      patient_id = create_patient
      payload = valid_related_person_payload(patient_id: patient_id).except("patient")

      post "/RelatedPerson", params: payload, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when patient references a non-existent patient" do
      post "/RelatedPerson", params: valid_related_person_payload(patient_id: "does-not-exist"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 for an invalid gender" do
      patient_id = create_patient

      post "/RelatedPerson", params: valid_related_person_payload(patient_id: patient_id, gender: "bogus"), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /RelatedPerson/:id" do
    it "returns the resource" do
      id = create_related_person(patient_id: create_patient)

      get "/RelatedPerson/#{id}"

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown id" do
      get "/RelatedPerson/does-not-exist"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT and DELETE" do
    it "updates and then deletes" do
      patient_id = create_patient
      id = create_related_person(patient_id: patient_id)

      put "/RelatedPerson/#{id}",
          params: valid_related_person_payload(patient_id: patient_id, active: false),
          as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["meta"]["versionId"]).to eq("2")

      delete "/RelatedPerson/#{id}"
      expect(response).to have_http_status(:no_content)

      get "/RelatedPerson/#{id}"
      expect(response).to have_http_status(:gone)
    end
  end

  describe "GET /RelatedPerson (search)" do
    it "finds by identifier" do
      create_related_person(patient_id: create_patient)

      get "/RelatedPerson", params: { identifier: "RP1" }

      bundle = JSON.parse(response.body)
      expect(bundle["type"]).to eq("searchset")
      expect(bundle["total"]).to eq(1)
    end

    it "finds by patient reference" do
      patient_id = create_patient
      create_related_person(patient_id: patient_id)

      get "/RelatedPerson", params: { patient: "Patient/#{patient_id}" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by relationship, gender, and birthdate" do
      create_related_person(patient_id: create_patient)

      get "/RelatedPerson", params: { relationship: "MTH", gender: "female", birthdate: "1970-04-01" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "finds by active" do
      create_related_person(patient_id: create_patient)

      get "/RelatedPerson", params: { active: "true" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    # name_text joins the official name and the kana representation, so a kana
    # search has to match on a word boundary rather than a prefix.
    it "finds by a kana name representation" do
      create_related_person(patient_id: create_patient)

      get "/RelatedPerson", params: { name: "ヤマダ" }

      expect(JSON.parse(response.body)["total"]).to eq(1)
    end

    it "includes the referenced Patient via RelatedPerson:patient" do
      patient_id = create_patient
      id = create_related_person(patient_id: patient_id)

      get "/RelatedPerson", params: { _id: id, _include: "RelatedPerson:patient" }

      bundle = JSON.parse(response.body)
      included = bundle["entry"].select { |entry| entry.dig("search", "mode") == "include" }
      expect(included.map { |entry| entry["resource"]["resourceType"] }).to eq(["Patient"])
    end

    # RelatedPerson.patient is 1..1, so every row is in exactly one compartment
    # and Patient/$everything picks it up without further configuration.
    it "is returned by Patient/$everything" do
      patient_id = create_patient
      create_related_person(patient_id: patient_id)

      get "/Patient/#{patient_id}/$everything"

      types = JSON.parse(response.body)["entry"].map { |entry| entry["resource"]["resourceType"] }
      expect(types).to include("RelatedPerson")
    end
  end

  describe "capability statement" do
    it "advertises RelatedPerson with its JP Core profile" do
      get "/metadata"

      resource = JSON.parse(response.body)["rest"].first["resource"].find { |r| r["type"] == "RelatedPerson" }
      expect(resource["profile"]).to eq("http://jpfhir.jp/fhir/core/StructureDefinition/JP_RelatedPerson")
      expect(resource["searchParam"].map { |p| p["name"] }).to include("name", "relationship", "patient")
    end
  end
end
