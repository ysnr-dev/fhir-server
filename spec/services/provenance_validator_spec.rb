require "rails_helper"

RSpec.describe ProvenanceValidator do
  def payload(overrides = {})
    {
      "resourceType" => "Provenance",
      "target" => [{ "reference" => "ServiceRequest/sr1" }],
      "recorded" => "2026-09-01T10:30:15+09:00",
      "agent" => [
        { "type" => { "coding" => [
            { "system" => "http://terminology.hl7.org/CodeSystem/provenance-participant-type",
              "code" => "enterer" }
          ] },
          "who" => { "reference" => "Practitioner/pr1" },
          "onBehalfOf" => { "reference" => "Practitioner/pr2" } }
      ]
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed 代行入力 provenance" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.errors).to be_empty
    expect(result.warnings).to be_empty
  end

  describe "target" do
    it "rejects a missing target" do
      result = described_class.call(payload.except("target"))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("Provenance.target is required")
    end

    it "rejects an empty target array" do
      result = described_class.call(payload("target" => []))

      expect(result).not_to be_valid
    end

    it "rejects a target entry without a reference" do
      result = described_class.call(payload("target" => [{ "display" => "オーダー" }]))

      expect(result).not_to be_valid
      expect(result.errors.first[:expression]).to eq(["Provenance.target[0].reference"])
    end

    # バージョン付き参照は FHIR 上は正当だが、このサーバーは参照を文字列一致で引くので
    # ?target= からも _revinclude からも外れる。拒否せず警告で知らせる。
    it "warns about a version-specific reference but stays valid" do
      result = described_class.call(
        payload("target" => [{ "reference" => "ServiceRequest/sr1/_history/2" }])
      )

      expect(result).to be_valid
      expect(result.warnings.first[:diagnostics]).to include("version-specific")
    end
  end

  describe "recorded" do
    it "rejects a missing recorded" do
      result = described_class.call(payload.except("recorded"))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("Provenance.recorded is required")
    end

    it "rejects an instant without a timezone" do
      result = described_class.call(payload("recorded" => "2026-09-01T10:30:15"))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("valid FHIR instant")
    end
  end

  describe "agent" do
    it "rejects a missing agent" do
      result = described_class.call(payload.except("agent"))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("Provenance.agent is required")
    end

    it "rejects an agent without who.reference" do
      result = described_class.call(payload("agent" => [{ "who" => { "display" => "誰か" } }]))

      expect(result).not_to be_valid
      expect(result.errors.first[:expression]).to eq(["Provenance.agent[0].who.reference"])
    end

    # agent.type は extensible binding なので、外れたコードは警告に留める。
    it "warns about an agent.type outside the value set but stays valid" do
      result = described_class.call(
        payload("agent" => [{ "type" => { "coding" => [{ "code" => "clerk" }] },
                              "who" => { "reference" => "Practitioner/pr1" } }])
      )

      expect(result).to be_valid
      expect(result.warnings.first[:diagnostics]).to include("outside the recommended value set")
    end
  end

  describe "occurred[x]" do
    it "accepts occurredDateTime alone" do
      expect(described_class.call(payload("occurredDateTime" => "2026-09-01"))).to be_valid
    end

    it "rejects occurredDateTime and occurredPeriod together" do
      result = described_class.call(
        payload("occurredDateTime" => "2026-09-01",
                "occurredPeriod" => { "start" => "2026-09-01T10:00:00+09:00" })
      )

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("choice")
    end
  end

  describe "signature (承認)" do
    let(:signature) do
      { "type" => [{ "system" => "urn:iso-astm:E1762-95:2013", "code" => "1.2.840.10065.1.12.1.5" }],
        "when" => "2026-09-01T11:00:00+09:00",
        "who" => { "reference" => "Practitioner/pr2" } }
    end

    it "accepts a complete verification signature" do
      expect(described_class.call(payload("signature" => [signature]))).to be_valid
    end

    it "rejects a signature without a coded type" do
      result = described_class.call(payload("signature" => [signature.merge("type" => [])]))

      expect(result).not_to be_valid
      expect(result.errors.first[:expression]).to eq(["Provenance.signature[0].type"])
    end

    it "rejects a signature without when" do
      result = described_class.call(payload("signature" => [signature.except("when")]))

      expect(result).not_to be_valid
      expect(result.errors.first[:expression]).to eq(["Provenance.signature[0].when"])
    end

    it "rejects a signature whose when is not an instant" do
      result = described_class.call(payload("signature" => [signature.merge("when" => "2026-09-01")]))

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("valid FHIR instant")
    end

    it "rejects a signature without who.reference" do
      result = described_class.call(payload("signature" => [signature.except("who")]))

      expect(result).not_to be_valid
      expect(result.errors.first[:expression]).to eq(["Provenance.signature[0].who.reference"])
    end
  end

  describe "entity" do
    it "accepts a bound role with what.reference" do
      result = described_class.call(
        payload("entity" => [{ "role" => "revision", "what" => { "reference" => "ServiceRequest/sr0" } }])
      )

      expect(result).to be_valid
    end

    # entity.role は required binding なので、agent.type と違いエラーにする。
    it "rejects a role outside the value set" do
      result = described_class.call(
        payload("entity" => [{ "role" => "amended", "what" => { "reference" => "ServiceRequest/sr0" } }])
      )

      expect(result).not_to be_valid
      expect(result.errors.first[:diagnostics]).to include("Invalid Provenance.entity.role")
    end

    it "rejects an entity without what.reference" do
      result = described_class.call(payload("entity" => [{ "role" => "source" }]))

      expect(result).not_to be_valid
      expect(result.errors.first[:expression]).to eq(["Provenance.entity[0].what.reference"])
    end
  end
end
