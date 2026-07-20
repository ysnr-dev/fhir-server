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
        "collected"  => { type: :datetime, column: :collected_time }
      }.freeze
    end
  end
end
