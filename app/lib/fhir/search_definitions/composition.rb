module Fhir
  module SearchDefinitions
    module Composition
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "type"       => { type: :token_or_text, text_column: :type_text },
        "category"   => { type: :token, column: :category_code },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        # Composition.author is 0..* references, so it is matched by jsonb
        # containment rather than an extracted column.
        "author"     => { type: :reference, multiple: true, jsonb_key: "author",
                           ref_path: %w[reference], target_type: "Practitioner" },
        "date"       => { type: :datetime, column: :composition_date },
        # Composition.section.entry (R4 標準)。診療記録が対象とする病名(プロブレム)は
        # C-CDA on FHIR Progress Note の problems_section (LOINC 11450-4) の entry に
        # 入るので、POS/POMR のカルテを 1 つのプロブレムで縦に読む絞り込みがこれで済む。
        # section[] の中の entry[] という配列の二重ネストなので、外側配列の jsonb_key に
        # 加えて、その要素の中でさらに辿る配列キーを nested_path で表す。containment は
        #   {"section":[{"entry":[{"reference":"Condition/x"}]}]}
        # になる。R4 の式は Composition.section.entry で、入れ子サブセクションは含まない。
        # element_match は付けない: 標準の entry はセクションの種類を限定しない。
        # 参照先は Any だが実用上 Condition なので、素の id には Condition/ を補う。
        "entry"      => { type: :reference, multiple: true, jsonb_key: "section",
                           nested_path: %w[entry], ref_path: %w[reference],
                           target_type: "Condition" },
        # 記録した診療科。オーダーの依頼科と同じローカル拡張(order-department)を引く。
        "department" => { type: :reference, multiple: true, jsonb_key: "extension",
                           ref_path: %w[valueReference reference], target_type: "Organization",
                           element_match: { "url" => ServiceRequest::DEPARTMENT_EXTENSION_URL } },
        # 記録した病棟(看護サマリなど)。オーダーの入院病棟と同じローカル拡張(order-ward)を引く。
        "ward"       => { type: :reference, multiple: true, jsonb_key: "extension",
                           ref_path: %w[valueReference reference], target_type: "Location",
                           element_match: { "url" => ServiceRequest::WARD_EXTENSION_URL } }
      }.freeze
    end
  end
end
