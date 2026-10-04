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
        # 標準外のローカル検索パラメータ。JASPEHR の回答は記入者を contained の Practitioner
        # (氏名だけ)で持ち、author は "#practitioner" を指すので、author では「この人が書いた
        # 回答」を引けない。氏名は姓名の間の空白の有無が揺れるので、空白を除いた列と比べる
        # (検索値も同じく空白を除く)。同姓同名は区別できない。
        "author-name"   => { type: :string, column: :author_name_key, compact: true },
        # source is Patient|Practitioner|PractitionerRole|RelatedPerson. target_type
        # only supplies the default type for a bare id (`?source=123`) and the chain
        # target, so Practitioner is the useful default; fully-qualified references
        # of any type still match.
        "source"        => { type: :reference, column: :source_reference, target_type: "Practitioner" },
        "authored"      => { type: :datetime, column: :authored },
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
                             element_match: { "url" => PROBLEM_EXTENSION_URL } },
        # 記録した診療科。オーダーの依頼科と同じローカル拡張(order-department)を引く。
        "department"    => { type: :reference, multiple: true, jsonb_key: "extension",
                             ref_path: %w[valueReference reference], target_type: "Organization",
                             element_match: { "url" => ServiceRequest::DEPARTMENT_EXTENSION_URL } }
      }.freeze
    end
  end
end
