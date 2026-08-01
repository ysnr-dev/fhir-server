module GroupPayloadHelper
  # An actual (roster-based) Group. member_ids are Patient logical ids, because
  # those are the members Group/$export resolves; pass member_ids: [] for an
  # empty cohort, or actual: false for a descriptive group (which grp-1 forbids
  # from having members at all).
  def valid_group_payload(member_ids: [], managing_entity_id: nil, **overrides)
    payload = {
      "resourceType" => "Group",
      "identifier" => [{ "system" => "http://example.org/group", "value" => "GRP1" }],
      "type" => "person",
      "actual" => true,
      "name" => "2026年度 特定健診対象者",
      "code" => {
        "coding" => [
          { "system" => "http://example.org/CodeSystem/cohort", "code" => "checkup-2026" }
        ]
      }
    }
    payload["member"] = member_ids.map { |id| { "entity" => { "reference" => "Patient/#{id}" } } } if member_ids.any?
    payload["managingEntity"] = { "reference" => "Organization/#{managing_entity_id}" } if managing_entity_id

    payload.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include GroupPayloadHelper, type: :request
end
