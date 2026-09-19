module Fhir
  module SearchDefinitions
    module DocumentReference
      PARAMS = {
        "identifier" => { type: :identifier },
        "status"     => { type: :token, column: :status },
        "type"       => { type: :token_or_text, text_column: :type_text },
        # category は 0..* なので平坦列を持たず、トークン索引だけで引く
        # (全 coding が索引されるので 2 つ目以降の分類でも当たる)。
        "category"   => { type: :token },
        "subject"    => { type: :reference, column: :subject_reference,
                           target_type: "Patient", aliases: %w[patient] },
        "date"       => { type: :datetime, column: :document_date }
      }.freeze
    end
  end
end
