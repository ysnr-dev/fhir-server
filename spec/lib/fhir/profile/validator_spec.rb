require "rails_helper"

RSpec.describe Fhir::Profile::Validator do
  PROFILE_URL = "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Foo".freeze

  def element(id, **rest)
    path = id.split(".").map { |segment| segment.split(":").first }.join(".")
    { "id" => id, "path" => path }.merge(rest.transform_keys(&:to_s))
  end

  def stub_definition(elements, url: PROFILE_URL, type: "Foo")
    definition = { "url" => url, "type" => type, "snapshot" => { "element" => elements } }
    allow(Fhir::Profile::DefinitionStore).to receive(:structure_definition).with(url).and_return(definition)
  end

  def call(payload, url: PROFILE_URL)
    described_class.call(payload, profile_url: url)
  end

  describe "unresolvable profile" do
    it "is a no-op (valid) rather than raising when the profile isn't vendored" do
      result = call({ "resourceType" => "Foo" }, url: "http://example.com/not-vendored")

      expect(result.valid?).to be(true)
    end
  end

  describe "cardinality" do
    before do
      stub_definition([
        element("Foo", min: 0, max: "*"),
        element("Foo.status", min: 1, max: "1", base: { "max" => "1" }, type: [{ "code" => "code" }]),
        element("Foo.note", min: 0, max: "2", base: { "max" => "*" }, type: [{ "code" => "string" }])
      ])
    end

    it "flags a missing required element" do
      result = call({ "resourceType" => "Foo" })

      expect(result.valid?).to be(false)
      expect(result.errors).to include(a_hash_including(code: "required", expression: ["Foo.status"]))
    end

    it "flags exceeding the max cardinality" do
      result = call({ "resourceType" => "Foo", "status" => "active", "note" => %w[a b c] })

      expect(result.errors).to include(a_hash_including(code: "structure", expression: ["Foo.note"]))
    end

    it "is valid when cardinality is satisfied" do
      result = call({ "resourceType" => "Foo", "status" => "active", "note" => ["a"] })

      expect(result.valid?).to be(true)
    end
  end

  describe "array-vs-singleton shape" do
    before do
      stub_definition([
        element("Foo", min: 0, max: "*"),
        element("Foo.status", min: 0, max: "1", base: { "max" => "1" }, type: [{ "code" => "code" }]),
        element("Foo.note", min: 0, max: "*", base: { "max" => "*" }, type: [{ "code" => "string" }])
      ])
    end

    it "rejects a singleton element represented as a JSON array" do
      result = call({ "resourceType" => "Foo", "status" => ["active"] })

      expect(result.errors).to include(a_hash_including(code: "structure", expression: ["Foo.status"]))
    end

    it "rejects a repeating element represented as a bare (non-array) value" do
      result = call({ "resourceType" => "Foo", "note" => "a" })

      expect(result.errors).to include(a_hash_including(code: "structure", expression: ["Foo.note"]))
    end
  end

  describe "unknown elements" do
    before do
      stub_definition([
        element("Foo", min: 0, max: "*"),
        element("Foo.status", min: 0, max: "1", base: { "max" => "1" }, type: [{ "code" => "code" }])
      ])
    end

    it "flags a key with no matching element" do
      result = call({ "resourceType" => "Foo", "bogus" => "x" })

      expect(result.errors).to include(a_hash_including(code: "structure", expression: ["Foo.bogus"]))
    end

    it "allows the underscore-prefixed primitive extension companion without validating its contents" do
      result = call({ "resourceType" => "Foo", "status" => "active", "_status" => { "id" => "1", "anything" => true } })

      expect(result.valid?).to be(true)
    end
  end

  describe "choice types (value[x])" do
    before do
      stub_definition([
        element("Foo", min: 0, max: "*"),
        element("Foo.value[x]", min: 0, max: "1", base: { "max" => "1" },
                type: [{ "code" => "boolean" }, { "code" => "dateTime" }])
      ])
    end

    it "accepts a valid concrete choice key" do
      expect(call({ "resourceType" => "Foo", "valueBoolean" => true }).valid?).to be(true)
    end

    it "rejects a choice key for a type that isn't declared" do
      result = call({ "resourceType" => "Foo", "valueString" => "x" })

      expect(result.errors).to include(a_hash_including(code: "structure", expression: ["Foo.valueString"]))
    end

    it "flags more than one concrete choice key present at once" do
      result = call({ "resourceType" => "Foo", "valueBoolean" => true, "valueDateTime" => "2026-01-01" })

      expect(result.errors).to include(a_hash_including(code: "invariant"))
    end
  end

  describe "primitive format" do
    before do
      stub_definition([
        element("Foo", min: 0, max: "*"),
        element("Foo.flag", min: 0, max: "1", base: { "max" => "1" }, type: [{ "code" => "boolean" }]),
        element("Foo.when", min: 0, max: "1", base: { "max" => "1" }, type: [{ "code" => "date" }])
      ])
    end

    it "accepts a valid primitive value" do
      expect(call({ "resourceType" => "Foo", "flag" => true, "when" => "2026-07-23" }).valid?).to be(true)
    end

    it "rejects a boolean represented as a string" do
      result = call({ "resourceType" => "Foo", "flag" => "true" })

      expect(result.errors).to include(a_hash_including(code: "value", expression: ["Foo.flag"]))
    end

    it "rejects a malformed date" do
      result = call({ "resourceType" => "Foo", "when" => "not-a-date" })

      expect(result.errors).to include(a_hash_including(code: "value", expression: ["Foo.when"]))
    end
  end

  describe "fixed[x] and pattern[x]" do
    before do
      stub_definition([
        element("Foo", min: 0, max: "*"),
        element("Foo.system", min: 0, max: "1", base: { "max" => "1" }, type: [{ "code" => "uri" }],
                fixedUri: "http://example.com/fixed"),
        element("Foo.coding", min: 0, max: "1", base: { "max" => "1" }, type: [{ "code" => "CodeableConcept" }],
                patternCodeableConcept: { "coding" => [{ "system" => "http://example.com/sys" }] })
      ])
    end

    it "accepts an exact fixed[x] match and rejects a mismatch" do
      expect(call({ "resourceType" => "Foo", "system" => "http://example.com/fixed" }).valid?).to be(true)

      result = call({ "resourceType" => "Foo", "system" => "http://example.com/other" })
      expect(result.errors).to include(a_hash_including(code: "value", expression: ["Foo.system"]))
    end

    it "accepts a pattern[x] superset and rejects a value missing the pattern" do
      ok = call({ "resourceType" => "Foo",
                   "coding" => { "coding" => [{ "system" => "http://example.com/sys", "code" => "extra-ok" }] } })
      expect(ok.valid?).to be(true)

      bad = call({ "resourceType" => "Foo", "coding" => { "coding" => [{ "system" => "http://other.com" }] } })
      expect(bad.errors).to include(a_hash_including(code: "value", expression: ["Foo.coding"]))
    end
  end

  describe "required bindings" do
    before do
      stub_definition([
        element("Foo", min: 0, max: "*"),
        element("Foo.status", min: 0, max: "1", base: { "max" => "1" }, type: [{ "code" => "code" }],
                binding: { "strength" => "required", "valueSet" => "http://example.com/vs" })
      ])
    end

    it "flags a code outside the bound value set" do
      allow(Fhir::Profile::DefinitionStore).to receive(:expansion).with("http://example.com/vs")
                                                                    .and_return(Set.new(%w[active inactive]))

      result = call({ "resourceType" => "Foo", "status" => "bogus" })
      expect(result.errors).to include(a_hash_including(code: "value", expression: ["Foo.status"]))
    end

    it "accepts a code inside the bound value set" do
      allow(Fhir::Profile::DefinitionStore).to receive(:expansion).with("http://example.com/vs")
                                                                    .and_return(Set.new(%w[active inactive]))

      expect(call({ "resourceType" => "Foo", "status" => "active" }).valid?).to be(true)
    end

    it "skips the check entirely when the value set can't be resolved" do
      allow(Fhir::Profile::DefinitionStore).to receive(:expansion).with("http://example.com/vs").and_return(nil)

      expect(call({ "resourceType" => "Foo", "status" => "anything-goes" }).valid?).to be(true)
    end
  end

  describe "slicing" do
    def sliced_definition(rules)
      [
        element("Foo", min: 0, max: "*"),
        element("Foo.identifier", min: 0, max: "*", base: { "max" => "*" },
                slicing: { "discriminator" => [{ "type" => "value", "path" => "system" }], "rules" => rules }),
        element("Foo.identifier:a", sliceName: "a", min: 1, max: "1"),
        element("Foo.identifier:a.system", min: 1, max: "1", base: { "max" => "1" }, type: [{ "code" => "uri" }],
                fixedUri: "http://example.com/a"),
        element("Foo.identifier:a.value", min: 1, max: "1", base: { "max" => "1" }, type: [{ "code" => "string" }])
      ]
    end

    context "open slicing" do
      before { stub_definition(sliced_definition("open")) }

      it "accepts an item matching the slice, and an unrelated unmatched item" do
        result = call({ "resourceType" => "Foo", "identifier" => [
                        { "system" => "http://example.com/a", "value" => "1" },
                        { "system" => "http://other.com", "value" => "2" }
                      ] })

        expect(result.valid?).to be(true)
      end

      it "flags a missing required slice (min 1)" do
        result = call({ "resourceType" => "Foo",
                         "identifier" => [{ "system" => "http://other.com", "value" => "2" }] })

        expect(result.errors).to include(a_hash_including(code: "required", expression: ["Foo.identifier"]))
      end

      it "flags a slice item that violates the slice's own narrowed constraints" do
        result = call({ "resourceType" => "Foo",
                         "identifier" => [{ "system" => "http://example.com/a" }] }) # missing required .value

        expect(result.errors).to include(a_hash_including(code: "required", expression: ["Foo.identifier[0].value"]))
      end
    end

    context "closed slicing" do
      before { stub_definition(sliced_definition("closed")) }

      it "flags an item that doesn't match any declared slice" do
        result = call({ "resourceType" => "Foo", "identifier" => [
                        { "system" => "http://example.com/a", "value" => "1" },
                        { "system" => "http://other.com", "value" => "2" }
                      ] })

        expect(result.errors).to include(a_hash_including(code: "structure", expression: ["Foo.identifier[1]"]))
      end
    end
  end

  describe "against the real vendored JP Core package" do
    let(:patient_profile) { "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Patient" }
    let(:medication_request_profile) { "http://jpfhir.jp/fhir/core/StructureDefinition/JP_MedicationRequest" }

    def valid_patient
      {
        "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "abc123" }],
        "name" => [{ "use" => "official", "family" => "山田", "given" => ["太郎"] }],
        "gender" => "male",
        "birthDate" => "1990-01-01"
      }
    end

    it "accepts a conformant JP_Patient" do
      expect(call(valid_patient, url: patient_profile).valid?).to be(true)
    end

    it "flags a missing required identifier" do
      payload = valid_patient.tap { |p| p.delete("identifier") }

      result = call(payload, url: patient_profile)
      expect(result.errors).to include(a_hash_including(code: "required", expression: ["Patient.identifier"]))
    end

    it "flags an unknown top-level element" do
      payload = valid_patient.merge("notARealField" => "oops")

      result = call(payload, url: patient_profile)
      expect(result.errors).to include(a_hash_including(code: "structure", expression: ["Patient.notARealField"]))
    end

    it "recurses one level into a nested JP Core extension profile (JP_Patient_Race constrains value[x] to CodeableConcept)" do
      payload = valid_patient.merge(
        "extension" => [{ "url" => "http://jpfhir.jp/fhir/core/Extension/StructureDefinition/JP_Patient_Race",
                           "valueString" => "wrong type" }]
      )

      result = call(payload, url: patient_profile)
      expect(result.errors).to include(a_hash_including(code: "structure", expression: ["Patient.extension[0].valueString"]))
    end

    it "enforces MedicationRequest identifier slicing (rpNumber/orderInRp required, 1..1 each)" do
      payload = {
        "resourceType" => "MedicationRequest",
        "status" => "active",
        "intent" => "order",
        "subject" => { "reference" => "Patient/abc" },
        "authoredOn" => "2026-07-23",
        "medicationCodeableConcept" => { "coding" => [{ "system" => "http://jpfhir.jp/fhir/core/CodeSystem/JP_YJCode", "code" => "1" }] },
        "identifier" => [
          { "system" => "http://jpfhir.jp/fhir/core/mhlw/IdSystem/Medication-RPGroupNumber", "value" => "1" }
        ]
      }

      result = call(payload, url: medication_request_profile)
      expect(result.errors).to include(
        a_hash_including(code: "required", diagnostics: a_string_including("orderInRp"))
      )
    end
  end
end
