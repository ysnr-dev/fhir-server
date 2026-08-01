module DevicePayloadHelper
  # Device has no mandatory elements; this fixture populates every extracted
  # search column so request specs can exercise each parameter. `patient` is
  # what places the device in a patient compartment, so it is optional here --
  # pass patient_id: nil for a shared device that belongs to no compartment.
  def valid_device_payload(patient_id: nil, owner_id: nil, **overrides)
    payload = {
      "resourceType" => "Device",
      "identifier" => [{ "system" => "http://example.org/device", "value" => "DEV1" }],
      "status" => "active",
      "type" => {
        "coding" => [
          { "system" => "http://snomed.info/sct", "code" => "706172005", "display" => "Ventilator" }
        ],
        "text" => "人工呼吸器"
      },
      "manufacturer" => "サンプル医療機器",
      "modelNumber" => "SM-100",
      "deviceName" => [{ "name" => "サンプル人工呼吸器", "type" => "user-friendly-name" }],
      "url" => "http://example.org/devices/DEV1"
    }
    payload["patient"] = { "reference" => "Patient/#{patient_id}" } if patient_id
    payload["owner"] = { "reference" => "Organization/#{owner_id}" } if owner_id

    payload.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include DevicePayloadHelper, type: :request
end
