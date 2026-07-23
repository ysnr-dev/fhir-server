require "rails_helper"

RSpec.describe Composition do
  def build_composition(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, type, category, subject, encounter, and date" do
      composition = build_composition(
        "status" => "final",
        "type" => { "coding" => [{ "code" => "18842-5", "display" => "Discharge summary" }], "text" => "退院時サマリ" },
        "category" => [{ "coding" => [{ "code" => "11488-4" }] }],
        "subject" => { "reference" => "Patient/abc123" },
        "encounter" => { "reference" => "Encounter/enc1" },
        "date" => "2026-07-22T10:00:00+09:00"
      )

      composition.sync_search_fields!

      expect(composition.status).to eq("final")
      expect(composition.type_code).to eq("18842-5")
      expect(composition.type_text).to eq("退院時サマリ Discharge summary")
      expect(composition.category_code).to eq("11488-4")
      expect(composition.subject_reference).to eq("Patient/abc123")
      expect(composition.encounter_reference).to eq("Encounter/enc1")
      expect(composition.composition_date).to eq(Time.iso8601("2026-07-22T10:00:00+09:00"))
    end

    it "is nil-safe when fields are absent" do
      composition = build_composition({})

      expect { composition.sync_search_fields! }.not_to raise_error
      expect(composition.status).to be_nil
      expect(composition.subject_reference).to be_nil
    end
  end

  describe "#sync_identifiers!" do
    it "extracts the single (0..1) identifier object" do
      composition = build_composition(
        "identifier" => { "system" => "http://example.org/composition", "value" => "COMP1" }
      )

      composition.save!(validate: false)
      composition.sync_identifiers!

      expect(composition.resource_identifiers.pluck(:system, :value))
        .to contain_exactly(["http://example.org/composition", "COMP1"])
    end
  end
end
