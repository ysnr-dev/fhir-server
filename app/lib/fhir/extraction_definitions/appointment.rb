module Fhir
  module ExtractionDefinitions
    module Appointment
      # Appointment has no single-valued Patient element: the patient is one of the
      # 1..* participants. Patient-compartment membership (Fhir::PatientCompartment)
      # is derived from single-valued, indexed reference columns, so the Patient
      # actor is flattened into patient_reference here -- without it an Appointment
      # would be invisible to Patient/$everything, Patient/$export and patient-context
      # reads. The 0..* `actor` search parameter still matches every participant by
      # jsonb containment (see SearchDefinitions::Appointment).
      # slot / basedOn / reasonReference are 0..* references, matched the same way.
      FIELDS = {
        status: { path: "status" },
        appointment_type: { path: "appointmentType", transform: :coding_code },
        patient_reference: { path: "participant", transform: :actor_patient_reference },
        start_time: { path: "start", transform: :datetime }
      }.freeze

      # participant.status sits inside the 0..* participant array; TokenExtractor's
      # path digs through the array, so "participant.status" yields one row per
      # participant ("この予約はまだ患者の承諾待ちか" を part-status で引ける)。
      TOKENS = {
        "status" => { path: "status", kind: :code },
        "appointment-type" => { path: "appointmentType", kind: :codeable_concept },
        "service-category" => { path: "serviceCategory", kind: :codeable_concept_list },
        "service-type" => { path: "serviceType", kind: :codeable_concept_list },
        "specialty" => { path: "specialty", kind: :codeable_concept_list },
        "reason-code" => { path: "reasonCode", kind: :codeable_concept_list },
        "part-status" => { path: "participant.status", kind: :code_list }
      }.freeze
    end
  end
end
