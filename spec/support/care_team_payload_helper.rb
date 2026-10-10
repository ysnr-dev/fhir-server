module CareTeamPayloadHelper
  KIND_SYSTEM = "http://fhir-client.local/CodeSystem/care-team-kind".freeze
  ROLE_SYSTEM = "http://fhir-client.local/CodeSystem/care-team-role".freeze

  # 組織的なチーム(患者を持たない)。subject_id: を渡すと患者のケアチームになる。
  def valid_care_team_payload(subject_id: nil, **overrides)
    payload = {
      "resourceType" => "CareTeam",
      "identifier" => [{ "system" => "http://example.org/care-team", "value" => "CT1" }],
      "status" => "active",
      "category" => [
        { "coding" => [{ "system" => KIND_SYSTEM, "code" => "nst", "display" => "栄養サポートチーム" }] }
      ],
      "name" => "栄養サポートチーム",
      "participant" => [
        { "role" => [{ "coding" => [{ "system" => ROLE_SYSTEM, "code" => "lead" }] }],
          "member" => { "reference" => "Practitioner/dr-1", "display" => "山田 太郎" } },
        { "role" => [{ "coding" => [{ "system" => ROLE_SYSTEM, "code" => "member" }] }],
          "member" => { "reference" => "Practitioner/ns-1", "display" => "鈴木 花子" } }
      ],
      "managingOrganization" => [{ "reference" => "Organization/self-org" }],
      "period" => { "start" => "2026-04-01" }
    }
    payload["subject"] = { "reference" => "Patient/#{subject_id}" } if subject_id
    payload.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include CareTeamPayloadHelper, type: :request
end
