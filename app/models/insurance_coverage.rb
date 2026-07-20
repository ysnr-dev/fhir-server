# Named InsuranceCoverage (not Coverage) to avoid colliding with Ruby's stdlib
# `Coverage` module (used by bootsnap's iseq cache), which breaks app boot if a
# top-level class named `Coverage` is autoloaded. polymorphic_name is overridden
# so the FHIR resourceType string "Coverage" -- used everywhere else (routes,
# ResourceRegistry, resource_identifiers/resource_versions polymorphic columns,
# extraction_fields) -- stays decoupled from the Ruby class name.
class InsuranceCoverage < ApplicationRecord
  include FhirResourceRecord

  self.table_name = "coverages"

  def self.polymorphic_name
    "Coverage"
  end
end
