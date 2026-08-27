module Fhir
  module SearchDefinitions
    module QuestionnaireResponse
      # テンプレート回答が対象とする病名(プロブレム)。Composition と同じ理由
      # (base に対象疾患を表す要素が無い)でルート直下の拡張に置かれる。
      PROBLEM_EXTENSION_URL = "http://fhir-client.local/StructureDefinition/questionnaire-response-problem".freeze

      PARAMS = {
        "identifier"    => { type: :identifier },
        # A canonical ("<url>|<version>"), not a Reference -- :uri, not :reference,
        # so it is never rewritten into "Questionnaire/{id}" and never chained.
        "questionnaire" => { type: :uri, column: :questionnaire_canonical },
        "status"        => { type: :token, column: :status },
        # Declaring subject as a single-valued Patient reference is what puts
        # QuestionnaireResponse in the patient compartment (see
        # Fhir::PatientCompartment), which in turn drives Patient/$everything,
        # Patient/$export and patient/*.read scoping.
        "subject"       => { type: :reference, column: :subject_reference,
                             target_type: "Patient", aliases: %w[patient] },
        "encounter"     => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        "author"        => { type: :reference, column: :author_reference, target_type: "Practitioner" },
        # source is Patient|Practitioner|PractitionerRole|RelatedPerson. target_type
        # only supplies the default type for a bare id (`?source=123`) and the chain
        # target, so Practitioner is the useful default; fully-qualified references
        # of any type still match.
        "source"        => { type: :reference, column: :source_reference, target_type: "Practitioner" },
        "authored"      => { type: :datetime, column: :authored },
        # 0..* references, so matched by jsonb containment rather than a column.
        "based-on"      => { type: :reference, multiple: true, jsonb_key: "basedOn",
                             ref_path: %w[reference], target_type: "ServiceRequest" },
        "part-of"       => { type: :reference, multiple: true, jsonb_key: "partOf",
                             ref_path: %w[reference], target_type: "Observation" },
        # 標準外のローカル検索パラメータ。base に対象疾患を表す要素が無いので
        # ルート直下の拡張を引く(extension[] は他の拡張と配列を共有するので url も
        # 一致条件に入れる)。診療記録は標準の Composition:entry で引けるため、
        # 同じ絞り込みでもこちらだけがローカルのままになっている。
        "problem"       => { type: :reference, multiple: true, jsonb_key: "extension",
                             ref_path: %w[valueReference reference], target_type: "Condition",
                             element_match: { "url" => PROBLEM_EXTENSION_URL } }
      }.freeze
    end
  end
end
