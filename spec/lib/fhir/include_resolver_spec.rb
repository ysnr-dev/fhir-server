require "rails_helper"

RSpec.describe Fhir::IncludeResolver do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def create_service_request(overrides = {})
    Fhir::Repository.create(
      "ServiceRequest",
      {
        "resourceType" => "ServiceRequest",
        "status" => "active",
        "intent" => "order",
        "subject" => { "reference" => "Patient/#{patient.id}" }
      }.deep_merge(overrides.deep_stringify_keys)
    )
  end

  def create_medication_request(overrides = {})
    Fhir::Repository.create(
      "MedicationRequest",
      {
        "resourceType" => "MedicationRequest",
        "status" => "active",
        "intent" => "order",
        "subject" => { "reference" => "Patient/#{patient.id}" }
      }.deep_merge(overrides.deep_stringify_keys)
    )
  end

  def create_practitioner
    Fhir::Repository.create(
      "Practitioner",
      { "resourceType" => "Practitioner",
        "identifier" => [{ "system" => "urn:example", "value" => "DR1" }] }
    )
  end

  def create_encounter(overrides = {})
    Fhir::Repository.create(
      "Encounter",
      {
        "resourceType" => "Encounter",
        "status" => "finished",
        "class" => { "code" => "AMB" },
        "subject" => { "reference" => "Patient/#{patient.id}" }
      }.deep_merge(overrides.deep_stringify_keys)
    )
  end

  def resolve(resource_type:, records:, params:)
    described_class.call(resource_type: resource_type, records: records, params: params)
  end

  describe "forward _include" do
    it "resolves a single-valued reference (MedicationRequest:subject -> Patient)" do
      medication_request = create_medication_request

      included = resolve(
        resource_type: "MedicationRequest",
        records: [medication_request],
        params: { "_include" => "MedicationRequest:subject" }
      )

      expect(included.map(&:id)).to eq([patient.id])
      expect(included.first).to be_a(Patient)
    end

    it "resolves a multi-valued reference (MedicationRequest:based-on -> ServiceRequest)" do
      service_request = create_service_request
      medication_request = create_medication_request(
        "basedOn" => [{ "reference" => "ServiceRequest/#{service_request.id}" }]
      )

      included = resolve(
        resource_type: "MedicationRequest",
        records: [medication_request],
        params: { "_include" => "MedicationRequest:based-on" }
      )

      expect(included.map(&:id)).to eq([service_request.id])
      expect(included.first).to be_a(ServiceRequest)
    end

    it "de-duplicates a target shared across records" do
      first = create_medication_request
      second = create_medication_request

      included = resolve(
        resource_type: "MedicationRequest",
        records: [first, second],
        params: { "_include" => "MedicationRequest:subject" }
      )

      expect(included.map(&:id)).to eq([patient.id])
    end
  end

  describe "reverse _revinclude" do
    it "finds sources via a multi-valued jsonb reference (ServiceRequest search)" do
      service_request = create_service_request
      medication_request = create_medication_request(
        "basedOn" => [{ "reference" => "ServiceRequest/#{service_request.id}" }]
      )

      included = resolve(
        resource_type: "ServiceRequest",
        records: [service_request],
        params: { "_revinclude" => "MedicationRequest:based-on" }
      )

      expect(included.map(&:id)).to eq([medication_request.id])
      expect(included.first).to be_a(MedicationRequest)
    end

    it "finds sources via a single-valued extracted column (Patient search)" do
      medication_request = create_medication_request

      included = resolve(
        resource_type: "Patient",
        records: [patient],
        params: { "_revinclude" => "MedicationRequest:subject" }
      )

      expect(included.map(&:id)).to eq([medication_request.id])
    end

    it "excludes deleted sources" do
      service_request = create_service_request
      medication_request = create_medication_request(
        "basedOn" => [{ "reference" => "ServiceRequest/#{service_request.id}" }]
      )
      Fhir::Repository.delete("MedicationRequest", medication_request)

      included = resolve(
        resource_type: "ServiceRequest",
        records: [service_request],
        params: { "_revinclude" => "MedicationRequest:based-on" }
      )

      expect(included).to be_empty
    end
  end

  describe "guards" do
    it "ignores unknown/unsupported tokens" do
      medication_request = create_medication_request

      included = resolve(
        resource_type: "MedicationRequest",
        records: [medication_request],
        params: { "_include" => "MedicationRequest:bogus", "_revinclude" => "Foo:bar" }
      )

      expect(included).to be_empty
    end

    it "short-circuits on an empty match set without querying" do
      included = resolve(
        resource_type: "ServiceRequest",
        records: [],
        params: { "_revinclude" => "MedicationRequest:based-on" }
      )

      expect(included).to be_empty
    end

    it "ignores a forward include whose source type is not the searched type" do
      medication_request = create_medication_request

      included = resolve(
        resource_type: "ServiceRequest",
        records: [medication_request],
        params: { "_include" => "MedicationRequest:subject" }
      )

      expect(included).to be_empty
    end
  end

  describe "single-valued references added in Tier 2" do
    it "forward-includes the encounter of a MedicationRequest" do
      encounter = create_encounter
      medication_request = create_medication_request("encounter" => { "reference" => "Encounter/#{encounter.id}" })

      included = resolve(
        resource_type: "MedicationRequest",
        records: [medication_request],
        params: { "_include" => "MedicationRequest:encounter" }
      )

      expect(included.map(&:id)).to eq([encounter.id])
      expect(included.first).to be_a(Encounter)
    end

    it "reverse-includes every Encounter of a patient (patient's clinical bundle)" do
      first = create_encounter
      second = create_encounter

      included = resolve(
        resource_type: "Patient",
        records: [patient],
        params: { "_revinclude" => "Encounter:subject" }
      )

      expect(included.map(&:id)).to contain_exactly(first.id, second.id)
    end

    it "follows a Location.partOf self-reference in reverse" do
      parent = Fhir::Repository.create("Location", { "resourceType" => "Location", "status" => "active", "name" => "棟" })
      child = Fhir::Repository.create(
        "Location",
        { "resourceType" => "Location", "status" => "active", "name" => "室",
          "partOf" => { "reference" => "Location/#{parent.id}" } }
      )

      included = resolve(
        resource_type: "Location",
        records: [parent],
        params: { "_revinclude" => "Location:partof" }
      )

      expect(included.map(&:id)).to eq([child.id])
    end
  end

  describe "multi-valued nested references (Encounter.participant)" do
    it "forward-includes the practitioner from a nested participant.individual" do
      practitioner = create_practitioner
      encounter = create_encounter(
        "participant" => [
          { "individual" => { "reference" => "Practitioner/#{practitioner.id}" } }
        ]
      )

      included = resolve(
        resource_type: "Encounter",
        records: [encounter],
        params: { "_include" => "Encounter:participant" }
      )

      expect(included.map(&:id)).to eq([practitioner.id])
      expect(included.first).to be_a(Practitioner)
    end

    it "reverse-includes encounters that reference a practitioner (via the practitioner alias)" do
      practitioner = create_practitioner
      encounter = create_encounter(
        "participant" => [
          { "individual" => { "reference" => "Practitioner/#{practitioner.id}" } }
        ]
      )

      included = resolve(
        resource_type: "Practitioner",
        records: [practitioner],
        params: { "_revinclude" => "Encounter:practitioner" }
      )

      expect(included.map(&:id)).to eq([encounter.id])
      expect(included.first).to be_a(Encounter)
    end
  end
end
