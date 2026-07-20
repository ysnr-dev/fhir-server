class ResourceVersion < ApplicationRecord
  belongs_to :resource, polymorphic: true, optional: true
end
