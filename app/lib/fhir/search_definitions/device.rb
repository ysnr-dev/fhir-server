module Fhir
  module SearchDefinitions
    module Device
      PARAMS = {
        "identifier"   => { type: :identifier },
        "status"       => { type: :token, column: :status },
        "type"         => { type: :token, column: :type_code },
        # Declaring patient as a single-valued Patient reference is what puts
        # Device in the patient compartment (see Fhir::PatientCompartment).
        "patient"      => { type: :reference, column: :patient_reference, target_type: "Patient" },
        # FHIR names Device.owner's search param "organization", not "owner".
        "organization" => { type: :reference, column: :owner_reference, target_type: "Organization" },
        "location"     => { type: :reference, column: :location_reference, target_type: "Location" },
        "manufacturer" => { type: :string, column: :manufacturer },
        "model"        => { type: :string, column: :model_number },
        # device_name_text is a space-joined multi-token column, so a plain prefix
        # match would only ever hit the first name (cf. Patient name / given).
        "device-name"  => { type: :string, column: :device_name_text, word_boundary: true },
        "url"          => { type: :uri, column: :url }
      }.freeze
    end
  end
end
