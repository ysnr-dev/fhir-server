require "rails_helper"

RSpec.describe CarePlan do
  def build_care_plan(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, intent, subject, encounter, the period, and the definition it came from" do
      care_plan = build_care_plan(
        "status" => "active",
        "intent" => "plan",
        "subject" => { "reference" => "Patient/abc123" },
        "encounter" => { "reference" => "Encounter/enc1" },
        "period" => { "start" => "2026-09-01", "end" => "2026-09-05" },
        "instantiatesCanonical" => ["http://example.org/PlanDefinition/path-1"],
        "instantiatesUri" => ["http://fhir-client.local/pathway/900001"]
      )

      care_plan.sync_search_fields!

      expect(care_plan.status).to eq("active")
      expect(care_plan.intent).to eq("plan")
      expect(care_plan.subject_reference).to eq("Patient/abc123")
      expect(care_plan.encounter_reference).to eq("Encounter/enc1")
      expect(care_plan.period_start).to be_present
      expect(care_plan.period_end).to be_present
      expect(care_plan.instantiates_canonical).to eq("http://example.org/PlanDefinition/path-1")
      expect(care_plan.instantiates_uri).to eq("http://fhir-client.local/pathway/900001")
    end

    # period.end が無い = まだ継続中。date 検索はこれを「終わっていない」と読む。
    it "leaves period_end null while the plan is still running" do
      care_plan = build_care_plan("status" => "active", "period" => { "start" => "2026-09-01" })

      care_plan.sync_search_fields!

      expect(care_plan.period_start).to be_present
      expect(care_plan.period_end).to be_nil
    end

    it "is nil-safe when fields are absent" do
      care_plan = build_care_plan({})

      care_plan.sync_search_fields!

      expect(care_plan.status).to be_nil
      expect(care_plan.subject_reference).to be_nil
      expect(care_plan.instantiates_uri).to be_nil
    end
  end

  describe "#sync_tokens!" do
    # category は 0..* で、意味のある coding が先頭とは限らないため列を持たない。
    # 全 coding が token 行になる。
    it "emits a token row for every category coding" do
      care_plan = build_care_plan(
        "status" => "active",
        "category" => [
          { "coding" => [{ "system" => "http://e-path.jp/fhir/ePath/CodeSystem/EPathBOMOutcomeCategoryCS",
                           "code" => "H" }] },
          { "coding" => [{ "system" => "http://e-path.jp/fhir/ePath/CodeSystem/EPathBOMOutcomeCodeCS",
                           "code" => "O00470" }] }
        ]
      )
      care_plan.save!

      care_plan.sync_tokens!

      categories = care_plan.resource_tokens.where(param_name: "category").pluck(:code)
      expect(categories).to contain_exactly("H", "O00470")
    end
  end
end
