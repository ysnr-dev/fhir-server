require "rails_helper"

RSpec.describe InsuranceCoverage do
  def build_coverage(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, type, beneficiary, and dependent" do
      coverage = build_coverage(
        "status" => "active",
        "type" => { "coding" => [{ "code" => "EHCPOL", "display" => "extended healthcare" }] },
        "beneficiary" => { "reference" => "Patient/abc123" },
        "payor" => [{ "reference" => "Organization/org1" }],
        "dependent" => "01"
      )

      coverage.sync_search_fields!

      expect(coverage.status).to eq("active")
      expect(coverage.type_code).to eq("EHCPOL")
      expect(coverage.type_text).to eq("extended healthcare")
      expect(coverage.beneficiary_reference).to eq("Patient/abc123")
      expect(coverage.dependent).to eq("01")
    end

    it "is nil-safe when fields are absent" do
      coverage = build_coverage({})

      expect { coverage.sync_search_fields! }.not_to raise_error
      expect(coverage.beneficiary_reference).to be_nil
      expect(coverage.status).to be_nil
    end
  end
end
