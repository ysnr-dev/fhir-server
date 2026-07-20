module Fhir
  module ExtractionDefinitions
    module ImagingStudy
      # modality is a 0..* array of bare Codings, so modality_code takes the first
      # coding's code.
      FIELDS = {
        status: { path: "status" },
        modality_code: { path: "modality", transform: :coding_list_code },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        started: { path: "started", transform: :datetime }
      }.freeze
    end
  end
end
