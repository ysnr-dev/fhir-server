# Normalized (system, code) rows extracted from a resource's coded elements, one row
# per coding, so token search can match on the full `system|code` pair (and every
# coding of a multi-coded CodeableConcept), mirroring ResourceIdentifier for identifiers.
class ResourceToken < ApplicationRecord
  belongs_to :resource, polymorphic: true, optional: true
end
