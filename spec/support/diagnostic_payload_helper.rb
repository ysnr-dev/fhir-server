module DiagnosticPayloadHelper
  def valid_specimen_payload(subject_id:, **overrides)
    {
      "resourceType" => "Specimen",
      "identifier" => [{ "system" => "http://example.org/specimen", "value" => "SP1" }],
      "status" => "available",
      "type" => {
        "coding" => [
          { "system" => "http://terminology.hl7.org/CodeSystem/v2-0487", "code" => "BLD", "display" => "Whole blood" }
        ]
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "collection" => { "collectedDateTime" => "2026-07-19T10:00:00+09:00" }
    }.deep_merge(overrides.deep_stringify_keys)
  end

  def valid_imaging_study_payload(subject_id:, **overrides)
    {
      "resourceType" => "ImagingStudy",
      "identifier" => [{ "system" => "urn:dicom:uid", "value" => "urn:oid:1.2.3.4" }],
      "status" => "available",
      "modality" => [
        { "system" => "http://dicom.nema.org/resources/ontology/DCM", "code" => "CT", "display" => "Computed Tomography" }
      ],
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "started" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end

  def valid_diagnostic_report_payload(subject_id:, **overrides)
    {
      "resourceType" => "DiagnosticReport",
      "identifier" => [{ "system" => "http://example.org/diagnostic-report", "value" => "DR1" }],
      "status" => "final",
      "category" => [
        { "coding" => [
          { "system" => "http://terminology.hl7.org/CodeSystem/v2-0074", "code" => "LAB", "display" => "Laboratory" }
        ] }
      ],
      "code" => {
        "coding" => [
          { "system" => "http://loinc.org", "code" => "58410-2", "display" => "CBC panel" }
        ],
        "text" => "血算"
      },
      "subject" => { "reference" => "Patient/#{subject_id}" },
      "effectiveDateTime" => "2026-07-19T10:00:00+09:00"
    }.deep_merge(overrides.deep_stringify_keys)
  end
end

RSpec.configure do |config|
  config.include DiagnosticPayloadHelper, type: :request
end
