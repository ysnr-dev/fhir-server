require "rails_helper"

RSpec.describe Fhir::Search do
  def create(type, content)
    Fhir::Repository.create(type, content.merge("resourceType" => type))
  end

  # Fhir::Search only accepts a Fhir::SearchParams; this wraps a plain params
  # Hash (String, Array, or "name:modifier" keys) the way SearchParams.from_hash
  # does, so existing test cases can stay concise.
  def search(type, params_hash)
    described_class.call(type, Fhir::SearchParams.from_hash(params_hash))
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
      result = search("Patient", { "_sort" => "family" })

      expect(result.records.map(&:family)).to eq(%w[Abe Baba Chen])
    end

    it "sorts descending with a - prefix" do
      result = search("Patient", { "_sort" => "-birthdate" })

      expect(result.records.map { |r| r.content["birthDate"] }).to eq(%w[2000-01-01 1990-01-01 1980-01-01])
    end

    it "supports multiple comma-separated sort keys with a tiebreaker" do
      create("Patient", { "identifier" => [{ "value" => "d" }],
                          "name" => [{ "use" => "official", "family" => "Abe" }], "birthDate" => "1970-01-01" })

      result = search("Patient", { "_sort" => "family,birthdate" })

      abe = result.records.select { |r| r.family == "Abe" }
      expect(result.records.map(&:family).first(2)).to eq(%w[Abe Abe])
      expect(abe.map { |r| r.content["birthDate"] }).to eq(%w[1970-01-01 1980-01-01])
    end

    it "ignores unknown/unsortable sort fields and falls back to id order" do
      result = search("Patient", { "_sort" => "identifier,bogus" })

      ids = result.records.map(&:id)
      expect(ids).to eq(ids.sort)
    end
  end

  describe "reference search" do
    it "matches a single-valued reference via the extracted column" do
      create("MedicationRequest", { "identifier" => [{ "value" => "m1" }], "status" => "active", "intent" => "order",
                                    "encounter" => { "reference" => "Encounter/enc-1" } })
      create("MedicationRequest", { "identifier" => [{ "value" => "m2" }], "status" => "active", "intent" => "order" })

      result = search("MedicationRequest", { "encounter" => "Encounter/enc-1" })

      expect(result.total).to eq(1)
    end

    it "matches a multi-valued participant reference via jsonb containment" do
      create("Encounter", { "identifier" => [{ "value" => "e1" }], "status" => "finished", "class" => { "code" => "AMB" },
                            "participant" => [{ "individual" => { "reference" => "Practitioner/other" } },
                                              { "individual" => { "reference" => "Practitioner/doc-1" } }] })
      create("Encounter", { "identifier" => [{ "value" => "e2" }], "status" => "finished", "class" => { "code" => "AMB" } })

      result = search("Encounter", { "participant" => "Practitioner/doc-1" })

      expect(result.total).to eq(1)
    end

    it "accepts the practitioner alias for the participant param" do
      create("Encounter", { "identifier" => [{ "value" => "e3" }], "status" => "finished", "class" => { "code" => "AMB" },
                            "participant" => [{ "individual" => { "reference" => "Practitioner/doc-2" } }] })

      result = search("Encounter", { "practitioner" => "Practitioner/doc-2" })

      expect(result.total).to eq(1)
    end

    it "matches a multi-valued location reference via jsonb containment" do
      create("Encounter", { "identifier" => [{ "value" => "e4" }], "status" => "finished", "class" => { "code" => "AMB" },
                            "location" => [{ "location" => { "reference" => "Location/room-1" } }] })

      result = search("Encounter", { "location" => "Location/room-1" })

      expect(result.total).to eq(1)
    end

    it "prefixes a bare id with the param's target type" do
      create("Location", { "identifier" => [{ "value" => "l1" }], "status" => "active",
                           "partOf" => { "reference" => "Location/parent-1" } })

      result = search("Location", { "partof" => "parent-1" })

      expect(result.total).to eq(1)
    end
  end

  describe "comma-joined values (OR within a clause)" do
    it "matches any token value" do
      create("Encounter", { "identifier" => [{ "value" => "or-1" }], "status" => "planned", "class" => { "code" => "AMB" } })
      create("Encounter", { "identifier" => [{ "value" => "or-2" }], "status" => "finished", "class" => { "code" => "AMB" } })
      create("Encounter", { "identifier" => [{ "value" => "or-3" }], "status" => "cancelled", "class" => { "code" => "AMB" } })

      result = search("Encounter", { "status" => "planned,finished" })

      expect(result.total).to eq(2)
    end
  end

  describe "repeated parameters (AND across clauses)" do
    it "intersects two date-range bounds" do
      create("Patient", { "identifier" => [{ "value" => "and-1" }], "birthDate" => "1985-06-15" })
      create("Patient", { "identifier" => [{ "value" => "and-2" }], "birthDate" => "1970-01-01" })

      result = search("Patient", { "birthdate" => ["ge1980-01-01", "le1999-12-31"] })

      expect(result.total).to eq(1)
      expect(result.records.first.content["identifier"].first["value"]).to eq("and-1")
    end
  end

  describe "string modifiers" do
    before do
      create("Patient", { "identifier" => [{ "value" => "mod-1" }],
                          "name" => [{ "use" => "official", "family" => "Yamada", "given" => ["Taro"] }] })
    end

    it "defaults to a starts-with match" do
      expect(search("Patient", { "family" => "Yama" }).total).to eq(1)
      expect(search("Patient", { "family" => "amada" }).total).to eq(0)
    end

    it "matches mid-string on word_boundary columns" do
      expect(search("Patient", { "given" => "Taro" }).total).to eq(1)
      expect(search("Patient", { "name" => "Taro" }).total).to eq(1)
    end

    it "supports the :contains modifier" do
      expect(search("Patient", { "family:contains" => "mad" }).total).to eq(1)
    end

    it "supports the :exact modifier" do
      expect(search("Patient", { "family:exact" => "Yamada" }).total).to eq(1)
      expect(search("Patient", { "family:exact" => "Yama" }).total).to eq(0)
    end

    it "ignores an unsupported modifier on a non-string type, skipping the clause entirely" do
      create("Patient", { "identifier" => [{ "value" => "mod-2" }], "gender" => "male" })

      result = search("Patient", { "gender:exact" => "female" })

      # The clause is dropped rather than applied, so BOTH patients (regardless of
      # gender) are still returned -- distinguishing "skip" from "no match".
      expect(result.total).to eq(2)
    end
  end

  describe "token system|code handling" do
    before do
      create("Encounter", { "identifier" => [{ "value" => "tok-1" }], "status" => "finished", "class" => { "code" => "AMB" } })
    end

    it "matches on code alone" do
      expect(search("Encounter", { "class" => "AMB" }).total).to eq(1)
    end

    it "matches when a system is prefixed, ignoring the system portion" do
      expect(search("Encounter", { "class" => "http://terminology.hl7.org/CodeSystem/v3-ActCode|AMB" }).total).to eq(1)
    end

    it "matches with an empty system prefix" do
      expect(search("Encounter", { "class" => "|AMB" }).total).to eq(1)
    end
  end

  describe "identifier system|code handling" do
    it "matches system|value" do
      create("Patient", { "identifier" => [{ "system" => "http://example.org/mrn", "value" => "mrn-1" }] })

      result = search("Patient", { "identifier" => "http://example.org/mrn|mrn-1" })

      expect(result.total).to eq(1)
    end

    it "matches a nil system with |value" do
      create("Patient", { "identifier" => [{ "value" => "no-system-1" }] })

      result = search("Patient", { "identifier" => "|no-system-1" })

      expect(result.total).to eq(1)
    end
  end

  describe "date interval precision" do
    before do
      create("Patient", { "identifier" => [{ "value" => "prec-1" }], "birthDate" => "2024-06-15" })
    end

    it "expands a year-precision value to a full-year interval for eq" do
      expect(search("Patient", { "birthdate" => "2024" }).total).to eq(1)
      expect(search("Patient", { "birthdate" => "2023" }).total).to eq(0)
    end

    it "supports the ne prefix" do
      expect(search("Patient", { "birthdate" => "ne2023" }).total).to eq(1)
      expect(search("Patient", { "birthdate" => "ne2024" }).total).to eq(0)
    end
  end

  describe "Encounter.date (period) search" do
    it "eq matches only when the search interval fully contains the period" do
      create("Encounter", { "identifier" => [{ "value" => "per-1" }], "status" => "finished", "class" => { "code" => "AMB" },
                            "period" => { "start" => "2026-07-19T00:30:00Z", "end" => "2026-07-19T01:00:00Z" } })

      expect(search("Encounter", { "date" => "2026-07-19" }).total).to eq(1)
      expect(search("Encounter", { "date" => "2026-07-18" }).total).to eq(0)
    end

    it "treats a NULL period.end as still ongoing for ge/lt" do
      create("Encounter", { "identifier" => [{ "value" => "per-2" }], "status" => "in-progress", "class" => { "code" => "AMB" },
                            "period" => { "start" => "2026-07-19T00:00:00Z" } })

      expect(search("Encounter", { "date" => "ge2000-01-01" }).total).to eq(1)
      expect(search("Encounter", { "date" => "lt2000-01-01" }).total).to eq(0)
    end
  end

  describe "lenient handling" do
    it "skips a clause with an unparseable date value" do
      create("Patient", { "identifier" => [{ "value" => "len-1" }], "birthDate" => "2024-06-15" })

      result = search("Patient", { "birthdate" => "not-a-date" })

      expect(result.total).to eq(1)
    end

    it "ignores an unknown parameter" do
      create("Patient", { "identifier" => [{ "value" => "len-2" }] })

      result = search("Patient", { "bogus-param" => "x" })

      expect(result.total).to eq(1)
    end
  end
end
