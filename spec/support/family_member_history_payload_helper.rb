module FamilyMemberHistoryPayloadHelper
  # JP Core の例と同じく、病名は text だけでも書ける。ここでは 1 件目にコードを付けて
  # コード検索とテキスト検索の両方を試せるようにしている。
  def valid_family_member_history_payload(patient_id:, **overrides)
    {
      "resourceType" => "FamilyMemberHistory",
      "identifier" => [{ "system" => "http://example.org/family-history", "value" => "FH1" }],
      "status" => "completed",
      "patient" => { "reference" => "Patient/#{patient_id}" },
      "date" => "2026-07-19T10:00:00+09:00",
      "relationship" => {
        "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/v3-RoleCode", "code" => "MTH", "display" => "mother" }]
      },
      "sex" => {
        "coding" => [{ "system" => "http://hl7.org/fhir/administrative-gender", "code" => "female" }]
      },
      "condition" => [
        { "code" => { "coding" => [{ "system" => "http://hl7.org/fhir/sid/icd-10", "code" => "E11" }], "text" => "糖尿病" } },
        { "code" => { "text" => "難聴" } }
      ]
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include FamilyMemberHistoryPayloadHelper, type: :request
end
