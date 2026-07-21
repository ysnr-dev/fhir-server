require "rails_helper"

RSpec.describe Fhir::CapabilityStatement do
  subject(:statement) { described_class.build(date: "2026-07-20T00:00:00Z") }

  def resource(type)
    statement["rest"].first["resource"].find { |r| r["type"] == type }
  end

  def search_param_names(type)
    resource(type)["searchParam"].map { |p| p["name"] }
  end

  it "builds an active FHIR R4 CapabilityStatement with the given date" do
    expect(statement).to include(
      "resourceType" => "CapabilityStatement",
      "status" => "active",
      "fhirVersion" => "4.0.1",
      "date" => "2026-07-20T00:00:00Z"
    )
  end

  it "advertises transaction, batch, and history-system at the server level" do
    codes = statement["rest"].first["interaction"].map { |i| i["code"] }
    expect(codes).to contain_exactly("transaction", "batch", "history-system")
  end

  it "lists every registered resource type with its JP Core profile" do
    types = statement["rest"].first["resource"].map { |r| r["type"] }
    expect(types).to eq(Fhir::ResourceRegistry.types)

    expect(resource("Patient")["profile"]).to eq("http://jpfhir.jp/fhir/core/StructureDefinition/JP_Patient")
    expect(resource("ServiceRequest")["profile"]).to eq("http://jpfhir.jp/fhir/core/StructureDefinition/JP_ServiceRequest_Common")
  end

  it "grants the full instance/type interaction set per resource" do
    codes = resource("Patient")["interaction"].map { |i| i["code"] }
    expect(codes).to eq(%w[read vread update patch delete history-instance history-type search-type create])
  end

  it "brackets the declared search params with _id and _lastUpdated" do
    expect(search_param_names("Patient")).to eq(
      %w[_id identifier name family given gender birthdate active _lastUpdated]
    )
  end

  it "derives FHIR search param types from the search definitions" do
    med = resource("MedicationRequest")["searchParam"]
    expect(med).to include(
      { "name" => "subject", "type" => "reference" },
      { "name" => "code", "type" => "token" },
      { "name" => "authoredon", "type" => "date" }
    )
  end

  it "advertises every param the search engine actually supports (incl. Practitioner birthdate)" do
    expect(search_param_names("Practitioner")).to include("birthdate")
  end
end
