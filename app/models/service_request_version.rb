class ServiceRequestVersion < ApplicationRecord
  belongs_to :service_request, foreign_key: :service_request_id, inverse_of: :service_request_versions
end
