module Fhir
  module ExtractionDefinitions
    module Goal
      # lifecycleStatus は primitive code、achievementStatus は 0..1 CodeableConcept。
      # category は 0..* なので平坦化した列は持たず resource_tokens だけで引く
      # (CarePlan.category と同じ理由)。
      FIELDS = {
        lifecycle_status: { path: "lifecycleStatus" },
        achievement_status: { path: "achievementStatus", transform: :coding_code },
        subject_reference: { path: "subject.reference" },
        # start[x] は choice。startDate(日付)だけを索引し、startCodeableConcept
        # (開始の契機)は日付として扱えないので採らない。
        start_date: { path: "startDate", transform: :partial_date }
      }.freeze

      # Token search sources (resource_tokens), keyed by canonical search-param name.
      TOKENS = {
        "lifecycle-status"   => { path: "lifecycleStatus", kind: :code },
        "achievement-status" => { path: "achievementStatus", kind: :codeable_concept },
        "category"           => { path: "category", kind: :codeable_concept_list }
      }.freeze
    end
  end
end
