class MedicationRequestVersion < ApplicationRecord
  belongs_to :medication_request, foreign_key: :medication_request_id, inverse_of: :medication_request_versions
end
