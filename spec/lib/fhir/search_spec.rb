require "rails_helper"

RSpec.describe Fhir::Search do
  def create(type, content)
    Fhir::Repository.create(type, content.merge("resourceType" => type))
  end

  describe "_sort" do
    before do
      create("Patient", { "identifier" => [{ "value" => "a" }],
                          "name" => [{ "use" => "official", "family" => "Chen" }], "birthDate" => "1990-01-01" })
      create("Patient", { "identifier" => [{ "value" => "b" }],
                          "name" => [{ "use" => "official", "family" => "Abe" }], "birthDate" => "1980-01-01" })
      create("Patient", { "identifier" => [{ "value" => "c" }],
                          "name" => [{ "use" => "official", "family" => "Baba" }], "birthDate" => "2000-01-01" })
    end

    it "sorts ascending by a mapped column" do
      result = described_class.call("Patient", { "_sort" => "family" })

      expect(result.records.map(&:family)).to eq(%w[Abe Baba Chen])
    end

    it "sorts descending with a - prefix" do
      result = described_class.call("Patient", { "_sort" => "-birthdate" })

      expect(result.records.map { |r| r.content["birthDate"] }).to eq(%w[2000-01-01 1990-01-01 1980-01-01])
    end

    it "supports multiple comma-separated sort keys with a tiebreaker" do
      create("Patient", { "identifier" => [{ "value" => "d" }],
                          "name" => [{ "use" => "official", "family" => "Abe" }], "birthDate" => "1970-01-01" })

      result = described_class.call("Patient", { "_sort" => "family,birthdate" })

      abe = result.records.select { |r| r.family == "Abe" }
      expect(result.records.map(&:family).first(2)).to eq(%w[Abe Abe])
      expect(abe.map { |r| r.content["birthDate"] }).to eq(%w[1970-01-01 1980-01-01])
    end

    it "ignores unknown/unsortable sort fields and falls back to id order" do
      result = described_class.call("Patient", { "_sort" => "identifier,bogus" })

      ids = result.records.map(&:id)
      expect(ids).to eq(ids.sort)
    end
  end

  describe "reference search" do
    it "matches a single-valued reference via the extracted column" do
      create("MedicationRequest", { "identifier" => [{ "value" => "m1" }], "status" => "active", "intent" => "order",
                                    "encounter" => { "reference" => "Encounter/enc-1" } })
      create("MedicationRequest", { "identifier" => [{ "value" => "m2" }], "status" => "active", "intent" => "order" })

      result = described_class.call("MedicationRequest", { "encounter" => "Encounter/enc-1" })

      expect(result.total).to eq(1)
    end

    it "matches a multi-valued participant reference via jsonb containment" do
      create("Encounter", { "identifier" => [{ "value" => "e1" }], "status" => "finished", "class" => { "code" => "AMB" },
                            "participant" => [{ "individual" => { "reference" => "Practitioner/other" } },
                                              { "individual" => { "reference" => "Practitioner/doc-1" } }] })
      create("Encounter", { "identifier" => [{ "value" => "e2" }], "status" => "finished", "class" => { "code" => "AMB" } })

      result = described_class.call("Encounter", { "participant" => "Practitioner/doc-1" })

      expect(result.total).to eq(1)
    end

    it "accepts the practitioner alias for the participant param" do
      create("Encounter", { "identifier" => [{ "value" => "e3" }], "status" => "finished", "class" => { "code" => "AMB" },
                            "participant" => [{ "individual" => { "reference" => "Practitioner/doc-2" } }] })

      result = described_class.call("Encounter", { "practitioner" => "Practitioner/doc-2" })

      expect(result.total).to eq(1)
    end

    it "matches a multi-valued location reference via jsonb containment" do
      create("Encounter", { "identifier" => [{ "value" => "e4" }], "status" => "finished", "class" => { "code" => "AMB" },
                            "location" => [{ "location" => { "reference" => "Location/room-1" } }] })

      result = described_class.call("Encounter", { "location" => "Location/room-1" })

      expect(result.total).to eq(1)
    end

    it "prefixes a bare id with the param's target type" do
      create("Location", { "identifier" => [{ "value" => "l1" }], "status" => "active",
                           "partOf" => { "reference" => "Location/parent-1" } })

      result = described_class.call("Location", { "partof" => "parent-1" })

      expect(result.total).to eq(1)
    end
  end
end
