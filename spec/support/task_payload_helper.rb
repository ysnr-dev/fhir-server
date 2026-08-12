module TaskPayloadHelper
  # A Task driving a ServiceRequest's workflow: `focus`/`basedOn` point at the
  # order, `for` at the patient whose compartment the Task belongs to, and
  # `owner` at whoever the work is assigned to. Pass for_id: nil for a Task
  # with no patient compartment (the validator warns rather than rejecting).
  def valid_task_payload(for_id: nil, service_request_id: nil, owner_id: nil,
                         requester_id: nil, encounter_id: nil, part_of_id: nil, **overrides)
    payload = {
      "resourceType" => "Task",
      "identifier" => [{ "system" => "http://example.org/task", "value" => "TSK1" }],
      "groupIdentifier" => { "system" => "http://example.org/order-group", "value" => "ORD-2026-0001" },
      "status" => "in-progress",
      "businessStatus" => {
        "coding" => [{ "system" => "http://example.org/CodeSystem/lab-workflow", "code" => "collected" }],
        "text" => "検体採取済"
      },
      "intent" => "order",
      "priority" => "routine",
      "code" => {
        "coding" => [{ "system" => "http://hl7.org/fhir/CodeSystem/task-code", "code" => "fulfill" }],
        "text" => "検査オーダーの実施"
      },
      "description" => "血液検査オーダーの実施",
      "performerType" => [
        { "coding" => [{ "system" => "http://terminology.hl7.org/CodeSystem/practitioner-role", "code" => "nurse" }] }
      ],
      "authoredOn" => "2026-08-12T09:00:00+09:00",
      "lastModified" => "2026-08-12T10:30:00+09:00",
      "executionPeriod" => { "start" => "2026-08-12T09:30:00+09:00", "end" => "2026-08-12T10:30:00+09:00" }
    }
    payload["for"] = { "reference" => "Patient/#{for_id}" } if for_id
    if service_request_id
      payload["focus"] = { "reference" => "ServiceRequest/#{service_request_id}" }
      payload["basedOn"] = [{ "reference" => "ServiceRequest/#{service_request_id}" }]
    end
    payload["owner"] = { "reference" => "Practitioner/#{owner_id}" } if owner_id
    payload["requester"] = { "reference" => "Practitioner/#{requester_id}" } if requester_id
    payload["encounter"] = { "reference" => "Encounter/#{encounter_id}" } if encounter_id
    payload["partOf"] = [{ "reference" => "Task/#{part_of_id}" }] if part_of_id

    payload.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include TaskPayloadHelper, type: :request
end
