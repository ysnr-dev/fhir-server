module Fhir
  module ExtractionDefinitions
    module Device
      # deviceName is 0..* backbone elements each carrying a `name`; they are
      # flattened into one space-joined column so the "device-name" search can
      # match any of them (the same shape as Patient.name_text).
      # udiCarrier is deliberately not extracted: it is 0..* and its searchable
      # values sit under the repeating element, which a dot path cannot fan out over.
      FIELDS = {
        status: { path: "status" },
        type_code: { path: "type", transform: :coding_code },
        patient_reference: { path: "patient.reference" },
        owner_reference: { path: "owner.reference" },
        location_reference: { path: "location.reference" },
        manufacturer: { path: "manufacturer" },
        model_number: { path: "modelNumber" },
        device_name_text: { path: "deviceName", transform: :name_list_text },
        url: { path: "url" }
      }.freeze

      TOKENS = {
        "status" => { path: "status", kind: :code },
        "type"   => { path: "type", kind: :codeable_concept }
      }.freeze
    end
  end
end
