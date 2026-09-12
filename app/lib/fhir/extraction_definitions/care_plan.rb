module Fhir
  module ExtractionDefinitions
    module CarePlan
      # status / intent は primitive code。category は 0..* CodeableConcept で、
      # 1 件の計画が「何の計画か」を複数の概念で並べるため平坦化した列は持たず
      # resource_tokens だけで突き合わせる(ServiceRequest.category と同じ理由)。
      # partOf / goal / addresses も 0..* の参照なので列を持たない(jsonb 包含で引く)。
      FIELDS = {
        status: { path: "status" },
        intent: { path: "intent" },
        subject_reference: { path: "subject.reference" },
        encounter_reference: { path: "encounter.reference" },
        period_start: { path: "period.start", transform: :datetime },
        period_end: { path: "period.end", transform: :datetime },
        # instantiatesCanonical / instantiatesUri はどちらも 0..* だが、実際に書かれるのは
        # 1 件なので先頭を採る(複数指す計画は検索対象外)。
        instantiates_canonical: { path: "instantiatesCanonical", transform: :first_value },
        instantiates_uri: { path: "instantiatesUri", transform: :first_value }
      }.freeze

      # Token search sources (resource_tokens), keyed by canonical search-param name.
      TOKENS = {
        "status"   => { path: "status", kind: :code },
        "intent"   => { path: "intent", kind: :code },
        "category" => { path: "category", kind: :codeable_concept_list }
      }.freeze
    end
  end
end
