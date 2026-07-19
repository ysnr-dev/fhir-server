class PatientVersion < ApplicationRecord
  belongs_to :patient, foreign_key: :patient_id, inverse_of: :patient_versions
end
