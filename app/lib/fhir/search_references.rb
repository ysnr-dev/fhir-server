module Fhir
  # Allow-list of the reference search parameters that `_include` / `_revinclude`
  # may traverse, keyed by "SourceType" then search parameter name. Only the
  # entries listed here are honored; anything else is ignored (per the FHIR spec,
  # a server may silently drop unsupported include parameters).
  #
  # Each definition describes how to read the reference out of the source's FHIR
  # `content`. Single-valued (0..1) and multi-valued (0..*) references use
  # different keys:
  #   targets   - resource types the reference is allowed to point at
  #   alias     - name of another param in the same source whose definition to use
  #
  #   single-valued:
  #     path    - keys to dig the reference string ("Type/id") out of `content`
  #     column  - extracted search column, used for indexed reverse lookups
  #
  #   multi-valued (multiple: true):
  #     jsonb_key - the `content` array key holding the repeating element
  #     ref_path  - keys from each array element down to the reference string;
  #                 used both to read refs (forward) and to build the jsonb
  #                 containment query (reverse), GIN-indexed on `content`
  module SearchReferences
    MAP = {
      "Encounter" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "service-provider" => { path: %w[serviceProvider reference], targets: %w[Organization], column: "service_provider_reference" },
        "location" => { multiple: true, jsonb_key: "location", ref_path: %w[location reference], targets: %w[Location] },
        "participant" => { multiple: true, jsonb_key: "participant", ref_path: %w[individual reference], targets: %w[Practitioner PractitionerRole] },
        "practitioner" => { alias: "participant" }
      },
      "MedicationRequest" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" },
        "requester" => { path: %w[requester reference], targets: %w[Practitioner PractitionerRole Organization], column: "requester_reference" },
        "based-on" => { multiple: true, jsonb_key: "basedOn", ref_path: %w[reference], targets: %w[ServiceRequest] }
      },
      "Medication" => {
        "manufacturer" => { path: %w[manufacturer reference], targets: %w[Organization], column: "manufacturer_reference" }
      },
      "MedicationDispense" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "context" => { path: %w[context reference], targets: %w[Encounter], column: "context_reference" },
        "prescription" => { multiple: true, jsonb_key: "authorizingPrescription", ref_path: %w[reference], targets: %w[MedicationRequest] }
      },
      "MedicationAdministration" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "context" => { path: %w[context reference], targets: %w[Encounter], column: "context_reference" },
        "request" => { path: %w[request reference], targets: %w[MedicationRequest], column: "request_reference" }
      },
      "MedicationStatement" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "context" => { path: %w[context reference], targets: %w[Encounter], column: "context_reference" }
      },
      "Observation" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" }
      },
      "Specimen" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" }
      },
      "ImagingStudy" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" }
      },
      "DiagnosticReport" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" },
        "result" => { multiple: true, jsonb_key: "result", ref_path: %w[reference], targets: %w[Observation] },
        "specimen" => { multiple: true, jsonb_key: "specimen", ref_path: %w[reference], targets: %w[Specimen] },
        # 結果の元になったオーダー(検体検査オーダーのヘッダ)。オーダーの検索に
        # _revinclude=DiagnosticReport:based-on を添えると「そのオーダーに結果が
        # 付いているか」を 1 リクエストで判定できる。
        "based-on" => { multiple: true, jsonb_key: "basedOn", ref_path: %w[reference], targets: %w[ServiceRequest] }
      },
      "ServiceRequest" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" },
        "requester" => { path: %w[requester reference], targets: %w[Practitioner PractitionerRole Organization], column: "requester_reference" },
        # ServiceRequest が別の ServiceRequest にぶら下がる形(オーダーのヘッダと明細)。
        # 親から子を引く _revinclude=ServiceRequest:based-on と、:iterate による
        # 2 段目(パネルの構成項目)の展開に使う。CarePlan は未実装なので載せない。
        "based-on" => { multiple: true, jsonb_key: "basedOn", ref_path: %w[reference], targets: %w[ServiceRequest] }
      },
      "Task" => {
        # Task.for の検索パラメータ名は FHIR 上 "subject"。patient はその別名。
        "subject" => { path: %w[for reference], targets: %w[Patient], column: "for_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" },
        "requester" => { path: %w[requester reference], column: "requester_reference",
                          targets: %w[Practitioner PractitionerRole Organization Patient Device RelatedPerson] },
        "owner" => { path: %w[owner reference], column: "owner_reference",
                      targets: %w[Practitioner PractitionerRole Organization Patient Device RelatedPerson] },
        # focus は作業対象そのもの、based-on は作業を生んだ依頼。オーダー画面は
        # _revinclude=Task:based-on で「そのオーダーが今どこまで進んだか」を引く。
        "focus" => { path: %w[focus reference], targets: %w[ServiceRequest], column: "focus_reference" },
        "based-on" => { multiple: true, jsonb_key: "basedOn", ref_path: %w[reference], targets: %w[ServiceRequest] },
        "part-of" => { multiple: true, jsonb_key: "partOf", ref_path: %w[reference], targets: %w[Task] }
      },
      "PractitionerRole" => {
        "practitioner" =>{ path: %w[practitioner reference], targets: %w[Practitioner], column: "practitioner_reference" },
        "organization" => { path: %w[organization reference], targets: %w[Organization], column: "organization_reference" }
      },
      "Location" => {
        "organization" => { path: %w[managingOrganization reference], targets: %w[Organization], column: "organization_reference" },
        "partof" => { path: %w[partOf reference], targets: %w[Location], column: "partof_reference" }
      },
      "Organization" => {
        "partof" => { path: %w[partOf reference], targets: %w[Organization], column: "partof_reference" }
      },
      "Condition" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" }
      },
      "AllergyIntolerance" => {
        "patient" => { path: %w[patient reference], targets: %w[Patient], column: "patient_reference" }
      },
      "Procedure" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" }
      },
      "Immunization" => {
        "patient" => { path: %w[patient reference], targets: %w[Patient], column: "patient_reference" }
      },
      "Coverage" => {
        "beneficiary" => { path: %w[beneficiary reference], targets: %w[Patient], column: "beneficiary_reference" },
        "patient" => { alias: "beneficiary" },
        "payor" => { multiple: true, jsonb_key: "payor", ref_path: %w[reference], targets: %w[Organization] }
      },
      "DocumentReference" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" }
      },
      "Composition" => {
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" },
        "author" => { multiple: true, jsonb_key: "author", ref_path: %w[reference],
                       targets: %w[Practitioner PractitionerRole Organization Device Patient RelatedPerson] }
      },
      # Questionnaire has no Reference elements, so it has no entry here.
      # QuestionnaireResponse.questionnaire is a canonical URL ("url" or
      # "url|version"), not a { "reference": "Type/id" } object, so it cannot be
      # traversed like the others; the canonical: definition below resolves it by
      # matching Questionnaire url (+ version) instead. Forward _include only --
      # _revinclude has no meaningful reverse form and is ignored.
      "QuestionnaireResponse" => {
        "questionnaire" => { canonical: true, path: %w[questionnaire], target: "Questionnaire",
                              url_column: :url, version_column: :version },
        "subject" => { path: %w[subject reference], targets: %w[Patient], column: "subject_reference" },
        "patient" => { alias: "subject" },
        "encounter" => { path: %w[encounter reference], targets: %w[Encounter], column: "encounter_reference" },
        "author" => { path: %w[author reference], targets: %w[Practitioner], column: "author_reference" },
        "source" => { path: %w[source reference], column: "source_reference",
                       targets: %w[Patient Practitioner PractitionerRole RelatedPerson] },
        "based-on" => { multiple: true, jsonb_key: "basedOn", ref_path: %w[reference],
                         targets: %w[CarePlan ServiceRequest] },
        "part-of" => { multiple: true, jsonb_key: "partOf", ref_path: %w[reference],
                        targets: %w[Observation Procedure] }
      },
      "Device" => {
        "patient" => { path: %w[patient reference], targets: %w[Patient], column: "patient_reference" },
        # FHIR names the search param after the target, not the element (Device.owner).
        "organization" => { path: %w[owner reference], targets: %w[Organization], column: "owner_reference" },
        "location" => { path: %w[location reference], targets: %w[Location], column: "location_reference" }
      },
      "RelatedPerson" => {
        "patient" => { path: %w[patient reference], targets: %w[Patient], column: "patient_reference" }
      },
      "Group" => {
        "managing-entity" => { path: %w[managingEntity reference], column: "managing_entity_reference",
                                targets: %w[Organization Practitioner PractitionerRole RelatedPerson] },
        # Group.member is 0..* and its reference sits one level below the array
        # element (member[].entity.reference), like Encounter:location.
        "member" => { multiple: true, jsonb_key: "member", ref_path: %w[entity reference],
                       targets: %w[Patient Practitioner PractitionerRole Device] }
      }
    }.freeze

    module_function

    # Parses an `_include`/`_revinclude` token of the form "Source:param" or
    # "Source:param:TargetType" and resolves it against the allow-list.
    # Returns { source_type:, param:, definition:, target_type: } or nil when the
    # token is unknown/unsupported (caller ignores nil).
    def lookup(token)
      return nil if token.blank?

      source_type, param, target_type = token.split(":", 3)
      return nil if source_type.blank? || param.blank?

      params_map = MAP[source_type]
      return nil unless params_map

      definition = params_map[param]
      return nil unless definition

      # Resolve aliases (e.g. "patient" -> "subject") to the canonical definition.
      if definition[:alias]
        param = definition[:alias]
        definition = params_map[param]
        return nil unless definition
      end

      # An optional third segment constrains the target type; reject if not allowed.
      # Canonical definitions have a single :target instead of :targets.
      allowed_targets = definition[:canonical] ? [definition[:target]] : definition[:targets]
      return nil if target_type.present? && !allowed_targets.include?(target_type)

      {
        source_type: source_type,
        param: param,
        definition: definition,
        target_type: target_type.presence
      }
    end
  end
end
