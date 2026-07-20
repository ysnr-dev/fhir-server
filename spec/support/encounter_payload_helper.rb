module EncounterPayloadHelper
  def valid_encounter_payload(overrides = {})
    {
      "resourceType" => "Encounter",
      "identifier" => [
        { "system" => "http://example.org/encounter", "value" => SecureRandom.hex(6) }
      ],
      "status" => "finished",
      "class" => {
        "system" => "http://terminology.hl7.org/CodeSystem/v3-ActCode",
        "code" => "AMB",
        "display" => "ambulatory"
      },
      "subject" => { "reference" => "Patient/#{SecureRandom.uuid}" },
      "period" => { "start" => "2026-07-19T09:00:00+09:00", "end" => "2026-07-19T10:00:00+09:00" }
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include EncounterPayloadHelper, type: :request
end
