require "rails_helper"

RSpec.describe Specimen do
  def build_specimen(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, type, subject, accession, and collected time" do
      specimen = build_specimen(
        "status" => "available",
        "type" => { "coding" => [{ "code" => "BLD" }] },
        "subject" => { "reference" => "Patient/abc123" },
        "accessionIdentifier" => { "system" => "http://example.org", "value" => "ACC-1" },
        "collection" => { "collectedDateTime" => "2026-07-19T10:00:00+09:00" }
      )

      specimen.sync_search_fields!

      expect(specimen.status).to eq("available")
      expect(specimen.type_code).to eq("BLD")
      expect(specimen.subject_reference).to eq("Patient/abc123")
      expect(specimen.accession_value).to eq("ACC-1")
      expect(specimen.collected_time).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
    end

    it "is nil-safe when fields are absent" do
      specimen = build_specimen({})

      expect { specimen.sync_search_fields! }.not_to raise_error
      expect(specimen.collected_time).to be_nil
      expect(specimen.type_code).to be_nil
    end
  end
end
