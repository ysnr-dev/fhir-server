require "rails_helper"

RSpec.describe Fhir::Search do
  include ActiveSupport::Testing::TimeHelpers

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
    let(:act_code) { "http://terminology.hl7.org/CodeSystem/v3-ActCode" }

    it "matches on code alone regardless of system" do
      create("Encounter", { "identifier" => [{ "value" => "tok-1" }], "status" => "finished",
                            "class" => { "system" => act_code, "code" => "AMB" } })

      expect(search("Encounter", { "class" => "AMB" }).total).to eq(1)
    end

    it "matches a full system|code pair" do
      create("Encounter", { "identifier" => [{ "value" => "tok-2" }], "status" => "finished",
                            "class" => { "system" => act_code, "code" => "AMB" } })

      expect(search("Encounter", { "class" => "#{act_code}|AMB" }).total).to eq(1)
    end

    it "distinguishes the same code under a different system" do
      create("Encounter", { "identifier" => [{ "value" => "tok-3" }], "status" => "finished",
                            "class" => { "system" => act_code, "code" => "AMB" } })
      create("Encounter", { "identifier" => [{ "value" => "tok-4" }], "status" => "finished",
                            "class" => { "system" => "http://example.org/local", "code" => "AMB" } })

      result = search("Encounter", { "class" => "#{act_code}|AMB" })

      expect(result.total).to eq(1)
      expect(result.records.first.content.dig("identifier", 0, "value")).to eq("tok-3")
    end

    it "matches any code within a system via system|" do
      create("Encounter", { "identifier" => [{ "value" => "tok-5" }], "status" => "finished",
                            "class" => { "system" => act_code, "code" => "AMB" } })
      create("Encounter", { "identifier" => [{ "value" => "tok-6" }], "status" => "planned",
                            "class" => { "system" => "http://example.org/local", "code" => "VR" } })

      expect(search("Encounter", { "class" => "#{act_code}|" }).total).to eq(1)
    end

    it "matches only codes with no system via |code" do
      create("Encounter", { "identifier" => [{ "value" => "tok-7" }], "status" => "finished",
                            "class" => { "code" => "AMB" } })
      create("Encounter", { "identifier" => [{ "value" => "tok-8" }], "status" => "finished",
                            "class" => { "system" => act_code, "code" => "AMB" } })

      result = search("Encounter", { "class" => "|AMB" })

      expect(result.total).to eq(1)
      expect(result.records.first.content.dig("identifier", 0, "value")).to eq("tok-7")
    end

    it "finds a resource by any of its multiple codings" do
      create("Observation", { "identifier" => [{ "value" => "multi-1" }], "status" => "final",
                              "code" => { "coding" => [
                                { "system" => "http://loinc.org", "code" => "1234-5" },
                                { "system" => "urn:oid:1.2.392.200119.4.504", "code" => "3B035" }
                              ] } })

      expect(search("Observation", { "code" => "http://loinc.org|1234-5" }).total).to eq(1)
      expect(search("Observation", { "code" => "urn:oid:1.2.392.200119.4.504|3B035" }).total).to eq(1)
    end

    it "still matches the free-text side of a token_or_text param" do
      create("Observation", { "identifier" => [{ "value" => "txt-1" }], "status" => "final",
                              "code" => { "text" => "血糖" } })

      expect(search("Observation", { "code" => "血糖" }).total).to eq(1)
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

  describe "chained search" do
    def create_patient_with_observation(family:, obs_identifier:)
      patient = create("Patient", { "identifier" => [{ "value" => "ch-#{family}" }],
                                    "name" => [{ "use" => "official", "family" => family }] })
      create("Observation", { "identifier" => [{ "value" => obs_identifier }], "status" => "final",
                              "code" => { "text" => "test" }, "subject" => { "reference" => "Patient/#{patient.id}" } })
      patient
    end

    it "matches through an untyped chain" do
      create_patient_with_observation(family: "山田", obs_identifier: "co-1")
      create_patient_with_observation(family: "佐藤", obs_identifier: "co-2")

      result = search("Observation", { "subject.family" => "山田" })

      expect(result.total).to eq(1)
      expect(result.records.first.content["identifier"].first["value"]).to eq("co-1")
    end

    it "matches through a typed chain with a tail modifier" do
      create_patient_with_observation(family: "山田", obs_identifier: "co-3")

      expect(search("Observation", { "subject:Patient.family:exact" => "山田" }).total).to eq(1)
      expect(search("Observation", { "subject:Patient.family:exact" => "山" }).total).to eq(0)
    end

    it "resolves the chain through a reference alias" do
      create_patient_with_observation(family: "田中", obs_identifier: "co-4")

      expect(search("Observation", { "patient.family" => "田中" }).total).to eq(1)
    end

    it "returns zero (not everything) when the chain matches no target" do
      create_patient_with_observation(family: "山田", obs_identifier: "co-5")

      expect(search("Observation", { "subject.family" => "存在しない" }).total).to eq(0)
    end

    it "treats a typed chain naming the wrong target type as unsupported (skipped)" do
      create_patient_with_observation(family: "山田", obs_identifier: "co-6")

      expect(search("Observation", { "subject:Practitioner.family" => "山田" }).total).to eq(1)
    end

    it "treats a multi-hop chain as unsupported (skipped)" do
      create_patient_with_observation(family: "山田", obs_identifier: "co-7")

      expect(search("Observation", { "subject.organization.name" => "x" }).total).to eq(1)
    end

    it "ORs comma values and ANDs repeated chained clauses" do
      create_patient_with_observation(family: "山田", obs_identifier: "co-8")
      create_patient_with_observation(family: "佐藤", obs_identifier: "co-9")

      expect(search("Observation", { "subject.family" => "山田,佐藤" }).total).to eq(2)
      expect(search("Observation", { "subject.family" => %w[山田 佐藤] }).total).to eq(0)
    end

    it "chains through a multi-valued reference (Encounter.location)" do
      location = create("Location", { "identifier" => [{ "value" => "loc-1" }], "name" => "第一診察室" })
      create("Encounter", { "identifier" => [{ "value" => "ch-enc-1" }], "status" => "finished", "class" => { "code" => "AMB" },
                            "location" => [{ "location" => { "reference" => "Location/#{location.id}" } }] })
      create("Encounter", { "identifier" => [{ "value" => "ch-enc-2" }], "status" => "finished", "class" => { "code" => "AMB" } })

      expect(search("Encounter", { "location.name" => "第一診察室" }).total).to eq(1)
      expect(search("Encounter", { "location.name" => "別の部屋" }).total).to eq(0)
    end
  end

  describe "_has (reverse chaining)" do
    def create_patient(value)
      create("Patient", { "identifier" => [{ "value" => value }] })
    end

    def create_observation_for(patient, code:)
      create("Observation", { "identifier" => [{ "value" => "has-obs-#{code}" }], "status" => "final",
                              "code" => { "coding" => [{ "system" => "http://loinc.org", "code" => code }], "text" => "t" },
                              "subject" => { "reference" => "Patient/#{patient.id}" } })
    end

    it "finds patients that have a matching observation (alias patient -> subject)" do
      with_obs = create_patient("has-1")
      create_patient("has-2")
      create_observation_for(with_obs, code: "1234-5")

      result = search("Patient", { "_has:Observation:patient:code" => "1234-5" })

      expect(result.total).to eq(1)
      expect(result.records.first.id).to eq(with_obs.id)
    end

    it "returns zero when no source resource matches" do
      create_patient("has-3")

      expect(search("Patient", { "_has:Observation:patient:code" => "9999-9" }).total).to eq(0)
    end

    it "treats unknown source types, unknown ref params, and nested _has as unsupported (skipped)" do
      create_patient("has-4")

      expect(search("Patient", { "_has:Bogus:patient:code" => "x" }).total).to eq(1)
      expect(search("Patient", { "_has:Observation:bogus-ref:code" => "x" }).total).to eq(1)
      expect(search("Patient", { "_has:Observation:patient:_has" => "x" }).total).to eq(1)
    end

    it "reverse-chains through a multi-valued source reference (Encounter.location)" do
      visited = create("Location", { "identifier" => [{ "value" => "has-loc-1" }], "name" => "処置室" })
      create("Location", { "identifier" => [{ "value" => "has-loc-2" }], "name" => "待合室" })
      create("Encounter", { "identifier" => [{ "value" => "has-enc-1" }], "status" => "finished", "class" => { "code" => "AMB" },
                            "location" => [{ "location" => { "reference" => "Location/#{visited.id}" } }] })

      result = search("Location", { "_has:Encounter:location:status" => "finished" })

      expect(result.total).to eq(1)
      expect(result.records.first.id).to eq(visited.id)
    end
  end

  describe ":missing modifier" do
    it "filters by NULL / NOT NULL on single-column params" do
      create("Patient", { "identifier" => [{ "value" => "mi-1" }], "gender" => "male" })
      create("Patient", { "identifier" => [{ "value" => "mi-2" }] })

      expect(search("Patient", { "gender:missing" => "true" }).total).to eq(1)
      expect(search("Patient", { "gender:missing" => "false" }).total).to eq(1)
    end

    it "requires both columns absent for token_or_text params" do
      create("Observation", { "identifier" => [{ "value" => "mi-3" }], "status" => "final",
                              "code" => { "text" => "血圧" } })

      expect(search("Observation", { "code:missing" => "false" }).total).to eq(1)
      expect(search("Observation", { "code:missing" => "true" }).total).to eq(0)
    end

    it "answers identifier:missing via the resource_identifiers table" do
      create("Patient", { "identifier" => [{ "value" => "mi-4" }] })
      create("Patient", {})

      expect(search("Patient", { "identifier:missing" => "true" }).total).to eq(1)
      expect(search("Patient", { "identifier:missing" => "false" }).total).to eq(1)
    end

    it "answers multi-valued reference :missing via jsonb key presence" do
      create("Encounter", { "identifier" => [{ "value" => "mi-5" }], "status" => "finished", "class" => { "code" => "AMB" },
                            "location" => [{ "location" => { "reference" => "Location/x" } }] })
      create("Encounter", { "identifier" => [{ "value" => "mi-6" }], "status" => "finished", "class" => { "code" => "AMB" } })

      expect(search("Encounter", { "location:missing" => "true" }).total).to eq(1)
      expect(search("Encounter", { "location:missing" => "false" }).total).to eq(1)
    end

    it "treats a period date as missing only when both columns are NULL" do
      create("Encounter", { "identifier" => [{ "value" => "mi-7" }], "status" => "in-progress", "class" => { "code" => "AMB" },
                            "period" => { "start" => "2026-07-19T00:00:00Z" } })
      create("Encounter", { "identifier" => [{ "value" => "mi-8" }], "status" => "planned", "class" => { "code" => "AMB" } })

      expect(search("Encounter", { "date:missing" => "true" }).total).to eq(1)
      expect(search("Encounter", { "date:missing" => "false" }).total).to eq(1)
    end

    it "treats values other than true/false as unsupported (skipped)" do
      create("Patient", { "identifier" => [{ "value" => "mi-9" }] })

      expect(search("Patient", { "gender:missing" => "maybe" }).total).to eq(1)
    end
  end

  describe "date prefixes sa / eb / ap" do
    it "sa/eb match strictly after/before the interval on point dates" do
      create("Patient", { "identifier" => [{ "value" => "dp-1" }], "birthDate" => "2024-06-15" })

      expect(search("Patient", { "birthdate" => "sa2024-06-14" }).total).to eq(1)
      expect(search("Patient", { "birthdate" => "sa2024-06-15" }).total).to eq(0)
      expect(search("Patient", { "birthdate" => "eb2024-06-16" }).total).to eq(1)
      expect(search("Patient", { "birthdate" => "eb2024-06-15" }).total).to eq(0)
    end

    it "sa/eb respect the NULL conventions on period dates" do
      create("Encounter", { "identifier" => [{ "value" => "dp-2" }], "status" => "in-progress", "class" => { "code" => "AMB" },
                            "period" => { "start" => "2026-07-01T00:00:00Z" } }) # no end: ongoing
      create("Encounter", { "identifier" => [{ "value" => "dp-3" }], "status" => "finished", "class" => { "code" => "AMB" },
                            "period" => { "start" => "2026-06-01T00:00:00Z", "end" => "2026-06-02T00:00:00Z" } })

      # Entirely after 2026-06-15: only the ongoing encounter starting 07-01.
      expect(search("Encounter", { "date" => "sa2026-06-15" }).total).to eq(1)
      # Entirely before 2026-06-15: only the closed June encounter; ongoing never qualifies.
      expect(search("Encounter", { "date" => "eb2026-06-15" }).total).to eq(1)
      expect(search("Encounter", { "date" => "eb2026-05-01" }).total).to eq(0)
    end

    it "ap widens the interval by 10% of the distance from now" do
      create("Patient", { "identifier" => [{ "value" => "dp-4" }], "birthDate" => "2026-01-11" })

      travel_to Time.zone.parse("2026-07-21T00:00:00Z") do
        # ~191 days from now => ~19-day tolerance: 2026-01-01 matches, 2025-11-01 does not.
        expect(search("Patient", { "birthdate" => "ap2026-01-01" }).total).to eq(1)
        expect(search("Patient", { "birthdate" => "ap2025-11-01" }).total).to eq(0)
      end
    end
  end

  describe "_summary=count and _total" do
    before do
      create("Patient", { "identifier" => [{ "value" => "sm-1" }] })
      create("Patient", { "identifier" => [{ "value" => "sm-2" }] })
    end

    it "_summary=count returns the total without fetching records" do
      result = search("Patient", { "_summary" => "count" })

      expect(result.total).to eq(2)
      expect(result.records).to eq([])
    end

    it "_total=none skips the count but still fetches records" do
      result = search("Patient", { "_total" => "none" })

      expect(result.total).to be_nil
      expect(result.records.length).to eq(2)
    end

    it "_summary=count wins over _total=none" do
      result = search("Patient", { "_summary" => "count", "_total" => "none" })

      expect(result.total).to eq(2)
    end

    it "_total=accurate and estimate return the exact count" do
      expect(search("Patient", { "_total" => "accurate" }).total).to eq(2)
      expect(search("Patient", { "_total" => "estimate" }).total).to eq(2)
    end
  end
end
