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
      expect(system_interactions).to include("transaction", "batch")
    end

    it "advertises conditional create and conditional update for every resource" do
      get "/metadata"

      resources = JSON.parse(response.body)["rest"].first["resource"]
      expect(resources).to all(include("conditionalCreate" => true, "conditionalUpdate" => true))
    end
  end
end
