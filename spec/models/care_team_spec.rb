require "rails_helper"

RSpec.describe CareTeam do
  def build_team(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, category, name, subject, managing organization, and the period" do
      team = build_team(
        "status" => "active",
        "category" => [
          { "coding" => [{ "system" => "http://fhir-client.local/CodeSystem/care-team-kind", "code" => "ict" }] }
        ],
        "name" => "感染対策チーム",
        "subject" => { "reference" => "Patient/abc123" },
        "managingOrganization" => [{ "reference" => "Organization/org-1" }],
        "period" => { "start" => "2026-04-01" }
      )

      team.sync_search_fields!

      expect(team.status).to eq("active")
      expect(team.category_code).to eq("ict")
      expect(team.name).to eq("感染対策チーム")
      expect(team.subject_reference).to eq("Patient/abc123")
      expect(team.managing_organization_reference).to eq("Organization/org-1")
      expect(team.period_start).to be_present
      expect(team.period_end).to be_nil
    end

    it "is nil-safe when fields are absent (an organizational team has no subject)" do
      team = build_team("status" => "active", "name" => "NST")

      team.sync_search_fields!

      expect(team.subject_reference).to be_nil
      expect(team.managing_organization_reference).to be_nil
      expect(team.category_code).to be_nil
    end
  end
end
