class CapabilityStatementsController < ApplicationController
  def show
    render_fhir_resource(capability_statement, status: :ok)
  end

  private

  def capability_statement
    {
      "resourceType" => "CapabilityStatement",
      "status" => "active",
      "date" => Time.current.utc.iso8601,
      "kind" => "instance",
      "fhirVersion" => "4.0.1",
      "format" => %w[application/fhir+json json],
      "rest" => [
        {
          "mode" => "server",
          "interaction" => %w[transaction batch].map { |code| { "code" => code } },
          "resource" => [
            {
              "type" => "Patient",
              "profile" => "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Patient",
              "interaction" => %w[read vread update delete history-instance search-type create].map { |code| { "code" => code } },
              "searchParam" => [
                { "name" => "_id", "type" => "token" },
                { "name" => "identifier", "type" => "token" },
                { "name" => "name", "type" => "string" },
                { "name" => "family", "type" => "string" },
                { "name" => "given", "type" => "string" },
                { "name" => "gender", "type" => "token" },
                { "name" => "birthdate", "type" => "date" },
                { "name" => "active", "type" => "token" },
                { "name" => "_lastUpdated", "type" => "date" }
              ]
            },
            {
              "type" => "MedicationRequest",
              "profile" => "http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationRequest",
              "interaction" => %w[read vread update delete history-instance search-type create].map { |code| { "code" => code } },
              "searchParam" => [
                { "name" => "_id", "type" => "token" },
                { "name" => "identifier", "type" => "token" },
                { "name" => "status", "type" => "token" },
                { "name" => "intent", "type" => "token" },
                { "name" => "subject", "type" => "reference" },
                { "name" => "code", "type" => "token" },
                { "name" => "authoredon", "type" => "date" },
                { "name" => "_lastUpdated", "type" => "date" }
              ]
            },
            {
              "type" => "ServiceRequest",
              "profile" => "http://jpfhir.jp/fhir/core/StructureDefinition/JP_ServiceRequest_Common",
              "interaction" => %w[read vread update delete history-instance search-type create].map { |code| { "code" => code } },
              "searchParam" => [
                { "name" => "_id", "type" => "token" },
                { "name" => "identifier", "type" => "token" },
                { "name" => "status", "type" => "token" },
                { "name" => "intent", "type" => "token" },
                { "name" => "subject", "type" => "reference" },
                { "name" => "code", "type" => "token" },
                { "name" => "authoredon", "type" => "date" },
                { "name" => "_lastUpdated", "type" => "date" }
              ]
            },
            {
              "type" => "Practitioner",
              "profile" => "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Practitioner",
              "interaction" => %w[read vread update delete history-instance search-type create].map { |code| { "code" => code } },
              "searchParam" => [
                { "name" => "_id", "type" => "token" },
                { "name" => "identifier", "type" => "token" },
                { "name" => "name", "type" => "string" },
                { "name" => "family", "type" => "string" },
                { "name" => "given", "type" => "string" },
                { "name" => "gender", "type" => "token" },
                { "name" => "active", "type" => "token" },
                { "name" => "_lastUpdated", "type" => "date" }
              ]
            },
            {
              "type" => "Organization",
              "profile" => "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Organization",
              "interaction" => %w[read vread update delete history-instance search-type create].map { |code| { "code" => code } },
              "searchParam" => [
                { "name" => "_id", "type" => "token" },
                { "name" => "identifier", "type" => "token" },
                { "name" => "name", "type" => "string" },
                { "name" => "active", "type" => "token" },
                { "name" => "_lastUpdated", "type" => "date" }
              ]
            }
          ]
        }
      ]
    }
  end
end
