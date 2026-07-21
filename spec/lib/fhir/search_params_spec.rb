require "rails_helper"

RSpec.describe Fhir::SearchParams do
  describe ".parse" do
    it "splits comma-joined values within one clause (OR)" do
      params = described_class.parse("status=active,completed")

      clause = params.clauses_for("status").first
      expect(clause.modifier).to be_nil
      expect(clause.values).to eq(%w[active completed])
    end

    it "preserves repeated parameter occurrences as separate clauses (AND)" do
      params = described_class.parse("date=ge2024-01-01&date=le2024-12-31")

      clauses = params.clauses_for("date")
      expect(clauses.size).to eq(2)
      expect(clauses.map { |c| c.values.first }).to eq(%w[ge2024-01-01 le2024-12-31])
    end

    it "extracts a modifier from the key" do
      params = described_class.parse("name:exact=Yamada")

      clause = params.clauses_for("name").first
      expect(clause.modifier).to eq("exact")
      expect(clause.values).to eq(%w[Yamada])
    end

    it "URL-decodes keys and values" do
      params = described_class.parse("gender=http%3A%2F%2Fhl7.org%2Ffhir%2Fadministrative-gender%7Cfemale")

      clause = params.clauses_for("gender").first
      expect(clause.values).to eq(%w[http://hl7.org/fhir/administrative-gender|female])
    end

    it "treats + as a space" do
      params = described_class.parse("name=Taro+Yamada")

      expect(params.clauses_for("name").first.values).to eq(["Taro Yamada"])
    end

    it "ignores an unknown/empty key" do
      params = described_class.parse("=bogus&&status=active")

      expect(params.clauses.map(&:name)).to eq(%w[status])
    end

    it "includes _id and _lastUpdated as normal clauses" do
      params = described_class.parse("_id=1,2&_lastUpdated=ge2024-01-01")

      expect(params.clauses_for("_id").first.values).to eq(%w[1 2])
      expect(params.clauses_for("_lastUpdated").first.values).to eq(%w[ge2024-01-01])
    end

    it "excludes meta parameters from #clauses" do
      params = described_class.parse("status=active&_sort=-date&_count=10&_offset=5&_include=Patient:subject&_revinclude=Observation:subject")

      expect(params.clauses.map(&:name)).to eq(%w[status])
    end
  end

  describe "#sort / #count / #offset" do
    it "returns the last occurrence when repeated" do
      params = described_class.parse("_sort=family&_count=10&_offset=0&_sort=-birthdate&_count=50&_offset=20")

      expect(params.sort).to eq("-birthdate")
      expect(params.count).to eq("50")
      expect(params.offset).to eq("20")
    end

    it "returns nil when absent" do
      params = described_class.parse("status=active")

      expect(params.sort).to be_nil
      expect(params.count).to be_nil
      expect(params.offset).to be_nil
    end

    it "preserves every comma-separated field in _sort's value, not just the first" do
      params = described_class.parse("_sort=family,birthdate")

      expect(params.sort).to eq("family,birthdate")
    end
  end

  describe "#includes / #revincludes" do
    it "flattens comma-joined and repeated occurrences, ignoring modified keys" do
      params = described_class.parse("_include=Patient:subject&_include=Encounter:location,Encounter:participant&_include:iterate=Patient:organization")

      expect(params.includes).to eq(%w[Patient:subject Encounter:location Encounter:participant])
    end

    it "flattens _revinclude the same way" do
      params = described_class.parse("_revinclude=MedicationRequest:subject,ServiceRequest:subject")

      expect(params.revincludes).to eq(%w[MedicationRequest:subject ServiceRequest:subject])
    end

    it "returns an empty array when absent" do
      params = described_class.parse("status=active")

      expect(params.includes).to eq([])
      expect(params.revincludes).to eq([])
    end
  end

  describe ".from_hash" do
    it "builds clauses from a plain Hash, comma-splitting values" do
      params = described_class.from_hash({ "status" => "active,completed", "_sort" => "family" })

      expect(params.clauses_for("status").first.values).to eq(%w[active completed])
      expect(params.sort).to eq("family")
    end

    it "builds one clause per Array element" do
      params = described_class.from_hash({ "date" => ["ge2024-01-01", "le2024-12-31"] })

      clauses = params.clauses_for("date")
      expect(clauses.size).to eq(2)
      expect(clauses.map { |c| c.values.first }).to eq(%w[ge2024-01-01 le2024-12-31])
    end

    it "extracts a modifier from a Hash key" do
      params = described_class.from_hash({ "name:contains" => "yama" })

      clause = params.clauses_for("name").first
      expect(clause.modifier).to eq("contains")
    end
  end

  describe "#to_query round-trip" do
    it "reproduces the same clauses after parse -> to_query -> parse" do
      original = described_class.parse(
        "status=active,completed&date=ge2024-01-01&date=le2024-12-31&name:exact=Yamada+Taro" \
        "&_sort=-date&_count=10&_include=Patient:subject&_revinclude=MedicationRequest:subject"
      )

      round_tripped = described_class.parse(original.to_query(offset: 0))

      expect(round_tripped.clauses).to eq(original.clauses)
      expect(round_tripped.sort).to eq(original.sort)
      expect(round_tripped.count).to eq(original.count)
      expect(round_tripped.includes).to eq(original.includes)
      expect(round_tripped.revincludes).to eq(original.revincludes)
    end

    it "escapes special characters (comma, colon, pipe, space) inside values" do
      original = described_class.parse("gender=http%3A%2F%2Fhl7.org%2Ffhir%2Fadministrative-gender%7Cfemale")

      round_tripped = described_class.parse(original.to_query(offset: 0))

      expect(round_tripped.clauses_for("gender").first.values).to eq(original.clauses_for("gender").first.values)
    end

    it "always appends _offset last with the given value" do
      params = described_class.parse("status=active")

      expect(params.to_query(offset: 40)).to end_with("&_offset=40")
    end

    it "omits _sort and _count when absent, but always includes _offset" do
      params = described_class.parse("status=active")

      query = params.to_query(offset: 0)
      expect(query).not_to include("_sort=")
      expect(query).not_to include("_count=")
      expect(query).to include("_offset=0")
    end

    it "round-trips chained and _has clauses byte-for-byte" do
      original = described_class.parse("subject:Patient.name=Yamada&encounter.status=finished&_has:Observation:patient:code=1234-5")

      round_tripped = described_class.parse(original.to_query(offset: 0))

      expect(round_tripped.clauses).to eq(original.clauses)
    end

    it "re-emits _summary, _elements, and _total in paging links" do
      params = described_class.parse("status=active&_summary=data&_elements=name,gender&_total=none")

      query = params.to_query(offset: 20)

      expect(query).to include("_summary=data", "_elements=name,gender", "_total=none")
      round_tripped = described_class.parse(query)
      expect(round_tripped.summary).to eq("data")
      expect(round_tripped.elements).to eq(%w[name gender])
      expect(round_tripped.total_mode).to eq("none")
    end
  end

  describe "Clause#chain" do
    def clause_for(query)
      described_class.parse(query).clauses.first
    end

    it "parses an untyped chain" do
      chain = clause_for("subject.name=Yamada").chain

      expect(chain.to_h).to include(base: "subject", target_type: nil, param: "name", tail_modifier: nil)
    end

    it "parses an untyped chain with a tail modifier" do
      chain = clause_for("subject.name:exact=Yamada").chain

      expect(chain.to_h).to include(base: "subject", target_type: nil, param: "name", tail_modifier: "exact")
    end

    it "parses a typed chain" do
      chain = clause_for("subject:Patient.name=Yamada").chain

      expect(chain.to_h).to include(base: "subject", target_type: "Patient", param: "name", tail_modifier: nil)
    end

    it "parses a typed chain with a tail modifier" do
      chain = clause_for("subject:Patient.name:exact=Yamada").chain

      expect(chain.to_h).to include(base: "subject", target_type: "Patient", param: "name", tail_modifier: "exact")
    end

    it "returns nil for plain and modifier-only clauses" do
      expect(clause_for("name=Yamada").chain).to be_nil
      expect(clause_for("name:exact=Yamada").chain).to be_nil
      expect(clause_for("gender:missing=true").chain).to be_nil
    end
  end

  describe "Clause#has" do
    def clause_for(query)
      described_class.parse(query).clauses.first
    end

    it "parses a _has clause" do
      has = clause_for("_has:Observation:patient:code=1234-5").has

      expect(has.to_h).to include(source_type: "Observation", ref_param: "patient", param: "code", tail_modifier: nil)
    end

    it "parses a _has clause with a tail modifier" do
      has = clause_for("_has:Observation:patient:code:exact=1234-5").has

      expect(has.to_h).to include(source_type: "Observation", ref_param: "patient", param: "code", tail_modifier: "exact")
    end

    it "returns nil for malformed _has and non-_has clauses" do
      expect(clause_for("_has:Observation:patient=x").has).to be_nil
      expect(clause_for("_has=x").has).to be_nil
      expect(clause_for("subject.name=x").has).to be_nil
    end
  end

  describe "#summary / #elements / #total_mode" do
    it "exposes the shaping meta params and keeps them out of clauses" do
      params = described_class.parse("status=active&_summary=count&_elements=name&_elements=gender,birthDate&_total=accurate")

      expect(params.summary).to eq("count")
      expect(params.elements).to eq(%w[name gender birthDate])
      expect(params.total_mode).to eq("accurate")
      expect(params.clauses.map(&:name)).to eq(%w[status])
    end

    it "returns nil/empty when absent" do
      params = described_class.parse("status=active")

      expect(params.summary).to be_nil
      expect(params.elements).to eq([])
      expect(params.total_mode).to be_nil
    end
  end
end
