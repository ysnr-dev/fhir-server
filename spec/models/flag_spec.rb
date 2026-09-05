require "rails_helper"

RSpec.describe Flag do
  def build_flag(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, category, code, subject, author, and the period" do
      flag = build_flag(
        "status" => "active",
        "category" => [
          { "coding" => [{ "system" => "http://fhir-client.local/CodeSystem/flag-category",
                           "code" => "clinical" }] }
        ],
        "code" => {
          "coding" => [{ "system" => "http://fhir-client.local/CodeSystem/patient-caution",
                         "code" => "implant", "display" => "体内金属・ペースメーカー" }],
          "text" => "心臓ペースメーカー"
        },
        "subject" => { "reference" => "Patient/abc123" },
        "author" => { "reference" => "Practitioner/pr1" },
        "period" => { "start" => "2026-09-01", "end" => "2026-09-30" }
      )

      flag.sync_search_fields!

      expect(flag.status).to eq("active")
      expect(flag.category_code).to eq("clinical")
      expect(flag.code_value).to eq("implant")
      # concept_text は text と先頭 coding の display を連結する(部分一致検索用)。
      expect(flag.code_text).to eq("心臓ペースメーカー 体内金属・ペースメーカー")
      expect(flag.subject_reference).to eq("Patient/abc123")
      expect(flag.author_reference).to eq("Practitioner/pr1")
      expect(flag.period_start).to be_present
      expect(flag.period_end).to be_present
    end

    # period.end が無い = まだ継続中。date 検索はこれを「終わっていない」と読む。
    it "leaves period_end null when the flag is still in effect" do
      flag = build_flag("status" => "active", "period" => { "start" => "2026-09-01" })

      flag.sync_search_fields!

      expect(flag.period_start).to be_present
      expect(flag.period_end).to be_nil
    end

    it "is nil-safe when fields are absent" do
      flag = build_flag({})

      flag.sync_search_fields!

      expect(flag.status).to be_nil
      expect(flag.category_code).to be_nil
      expect(flag.subject_reference).to be_nil
    end
  end
end
