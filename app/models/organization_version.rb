class OrganizationVersion < ApplicationRecord
  belongs_to :organization, foreign_key: :organization_id, inverse_of: :organization_versions
end
