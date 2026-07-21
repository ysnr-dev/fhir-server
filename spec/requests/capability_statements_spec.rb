require "rails_helper"

RSpec.describe "CapabilityStatement", type: :request do
  describe "GET /metadata" do
    it "returns a CapabilityStatement describing the Patient resource" do
      get "/metadata"

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/fhir+json")

      body = JSON.parse(response.body)
      expect(body["resourceType"]).to eq("CapabilityStatement")
      resource_types = body["rest"].first["resource"].map { |r| r["type"] }
      expect(resource_types).to include("Patient", "MedicationRequest", "ServiceRequest", "Practitioner", "Organization")

      system_interactions = body["rest"].first["interaction"].map { |i| i["code"] }
      expect(system_interactions).to include("transaction", "batch", "history-system")
    end

    it "advertises patch and history-type for every resource" do
      get "/metadata"

      resources = JSON.parse(response.body)["rest"].first["resource"]
      resources.each do |resource|
        codes = resource["interaction"].map { |i| i["code"] }
        expect(codes).to include("patch", "history-type", "history-instance")
      end
    end

    it "advertises searchInclude and searchRevInclude derived from the include allow-list" do
      get "/metadata"

      resources = JSON.parse(response.body)["rest"].first["resource"]
      observation = resources.find { |r| r["type"] == "Observation" }
      expect(observation["searchInclude"]).to include("Observation:subject", "Observation:patient", "Observation:encounter")

      patient = resources.find { |r| r["type"] == "Patient" }
      expect(patient["searchRevInclude"]).to include("Observation:subject", "MedicationRequest:subject", "Coverage:beneficiary")
    end

    it "advertises $validate on every resource and $everything on Patient" do
      get "/metadata"

      resources = JSON.parse(response.body)["rest"].first["resource"]
      resources.each do |resource|
        expect(resource["operation"].map { |o| o["name"] }).to include("validate")
      end

      patient = resources.find { |r| r["type"] == "Patient" }
      expect(patient["operation"].map { |o| o["name"] }).to include("everything")
      observation = resources.find { |r| r["type"] == "Observation" }
      expect(observation["operation"].map { |o| o["name"] }).not_to include("everything")
    end

    it "advertises conditional create/update/delete for every resource" do
      get "/metadata"

      resources = JSON.parse(response.body)["rest"].first["resource"]
      expect(resources).to all(
        include("conditionalCreate" => true, "conditionalRead" => "full-support",
                "conditionalUpdate" => true, "conditionalDelete" => "single")
      )
    end
  end
end
