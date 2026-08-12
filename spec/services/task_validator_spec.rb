require "rails_helper"

RSpec.describe TaskValidator do
  let(:patient) do
    Fhir::Repository.create(
      "Patient",
      { "resourceType" => "Patient",
        "identifier" => [{ "system" => "urn:oid:1.2.392.100495.20.3.51", "value" => "P1" }] }
    )
  end

  def payload(overrides = {})
    {
      "resourceType" => "Task",
      "status" => "in-progress",
      "intent" => "order",
      "priority" => "routine",
      "for" => { "reference" => "Patient/#{patient.id}" },
      "authoredOn" => "2026-08-12T09:00:00+09:00",
      "lastModified" => "2026-08-12T10:30:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  it "is valid for a well-formed task" do
    result = described_class.call(payload)

    expect(result).to be_valid
    expect(result.errors).to be_empty
    expect(result.warnings).to be_empty
  end

  describe "status / intent / priority" do
    it "rejects a missing status" do
      result = described_class.call(payload.except("status"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("required")
    end

    it "rejects a missing intent" do
      result = described_class.call(payload.except("intent"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("required")
    end

    it "rejects a status outside the task-status ValueSet" do
      result = described_class.call(payload("status" => "revoked"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("value")
    end

    # task-intent adds "unknown" on top of request-intent; ServiceRequest's
    # ValueSet does not have it, so the two bindings are genuinely different.
    it "accepts the Task-only intent 'unknown'" do
      expect(described_class.call(payload("intent" => "unknown"))).to be_valid
    end

    it "rejects an intent outside the task-intent ValueSet" do
      result = described_class.call(payload("intent" => "directive"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("value")
    end

    it "rejects a priority outside the request-priority ValueSet" do
      result = described_class.call(payload("priority" => "immediate"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("value")
    end

    it "accepts an absent priority" do
      expect(described_class.call(payload.except("priority"))).to be_valid
    end
  end

  describe "inv-1 (lastModified >= authoredOn)" do
    it "rejects a lastModified before authoredOn" do
      result = described_class.call(payload("lastModified" => "2026-08-12T08:00:00+09:00"))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("invariant")
    end

    it "accepts a lastModified equal to authoredOn" do
      expect(described_class.call(payload("lastModified" => "2026-08-12T09:00:00+09:00"))).to be_valid
    end

    it "does not double-report a malformed lastModified as an invariant failure" do
      result = described_class.call(payload("lastModified" => "not-a-date"))

      expect(result.errors.map { |e| e[:code] }).to eq(["value"])
    end

    it "skips the check when either timestamp is absent" do
      expect(described_class.call(payload.except("lastModified"))).to be_valid
      expect(described_class.call(payload.except("authoredOn"))).to be_valid
    end
  end

  describe "Task.for" do
    it "rejects a reference to a non-existent Patient" do
      result = described_class.call(payload("for" => { "reference" => "Patient/does-not-exist" }))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("invalid")
    end

    # Task.for is Reference(Any); only Patient references are looked up.
    it "accepts a non-Patient reference without a lookup" do
      expect(described_class.call(payload("for" => { "reference" => "Group/g1" }))).to be_valid
    end

    # Absent `for` means the Task has no patient compartment -- valid FHIR, but
    # worth telling the client about, so it warns rather than rejecting.
    it "warns but stays valid when for is absent" do
      result = described_class.call(payload.except("for"))

      expect(result).to be_valid
      expect(result.warnings.first[:expression]).to eq(["Task.for"])
    end
  end

  describe "basedOn / partOf" do
    it "accepts arrays of references" do
      result = described_class.call(payload(
                                      "basedOn" => [{ "reference" => "ServiceRequest/sr1" }],
                                      "partOf" => [{ "reference" => "Task/t1" }]
                                    ))

      expect(result).to be_valid
    end

    it "rejects a non-array basedOn, which search could never match" do
      result = described_class.call(payload("basedOn" => { "reference" => "ServiceRequest/sr1" }))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("structure")
    end

    it "rejects a non-array partOf" do
      result = described_class.call(payload("partOf" => { "reference" => "Task/t1" }))

      expect(result).not_to be_valid
      expect(result.errors.first[:code]).to eq("structure")
    end
  end
end
