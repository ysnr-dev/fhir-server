module Fhir
  module SearchDefinitions
    module Specimen
      PARAMS = {
        "identifier" => { type: :identifier },
        "accession"  => { type: :token, column: :accession_value },
        "status"     => { type: :token, column: :status },
        "type"       => { type: :token, column: :type_code },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        # Specimen.request は採取の元になったオーダー(検体検査の ServiceRequest)。
        # 0..* references なので jsonb containment で突き合わせる。fhir-client の
        # 検体検査ワークリストが「このオーダーの管」を引くのに使う。
        "request"    => { type: :reference, multiple: true, jsonb_key: "request",
                           ref_path: %w[reference], target_type: "ServiceRequest" },
        "collected"  => { type: :datetime, column: :collected_time }
      }.freeze
    end
  end
end
