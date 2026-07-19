class PractitionerVersion < ApplicationRecord
  belongs_to :practitioner, foreign_key: :practitioner_id, inverse_of: :practitioner_versions
end
