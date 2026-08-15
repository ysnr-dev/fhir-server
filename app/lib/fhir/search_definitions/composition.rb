module Fhir
  module SearchDefinitions
    module Composition
      # 診療記録が対象とする病名(プロブレム)。base Composition に対象疾患を表す
      # 要素が無い(event は検査・手術などの「行為」用)ため、書き手はルート直下の
      # 拡張に Condition 参照を置く。POS/POMR のカルテを 1 つのプロブレムで縦に
      # 読むための絞り込みなので、サーバー側でも引けるようにする。
      PROBLEM_EXTENSION_URL = "http://fhir-client.local/StructureDefinition/clinical-note-problem".freeze

      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "type"       => { type: :token_or_text, token_column: :type_code, text_column: :type_text },
        "category"   => { type: :token, column: :category_code },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "encounter"  => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        # Composition.author is 0..* references, so it is matched by jsonb
        # containment rather than an extracted column.
        "author"     => { type: :reference, multiple: true, jsonb_key: "author",
                           ref_path: %w[reference], target_type: "Practitioner" },
        "date"       => { type: :datetime, column: :composition_date },
        # 標準外のローカル検索パラメータ。extension[] は他の拡張と同じ配列を共有
        # するので、element_match で url も一致条件に入れる(参照だけで突き合わせると
        # 将来ルート直下に別の valueReference 拡張を足したときに誤って一致する)。
        # Fhir::SearchReferences には載せていないので _include/_revinclude では辿れない。
        "problem"    => { type: :reference, multiple: true, jsonb_key: "extension",
                           ref_path: %w[valueReference reference], target_type: "Condition",
                           element_match: { "url" => PROBLEM_EXTENSION_URL } }
      }.freeze
    end
  end
end
