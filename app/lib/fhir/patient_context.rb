module Fhir
  # The patient compartment an interactively-launched token is confined to.
  # Built from the token (ApplicationController#access_context) and threaded
  # through the read paths; a nil context anywhere means "unconfined", which is
  # how Backend Services tokens keep their existing behaviour.
  #
  # Two complementary checks, because reads arrive two ways:
  #   * #base_scope_for  -- narrows a query before it runs (search, _include)
  #   * #allows_record?  -- vets a row already loaded by id (read, vread)
  #
  # Both fail closed. A type whose compartment membership cannot be determined
  # is denied rather than allowed, so registering a new resource type never
  # silently widens what a patient can see.
  class PatientContext
    # Types with no Patient reference that are nonetheless readable in full:
    # shared terminology and directory data that a patient's own records point
    # at and cannot be resolved without.
    #
    # Binary is deliberately absent even though it has no Patient reference --
    # it holds document payloads, so treating it as "not patient data" would
    # expose every patient's attachments. It stays denied until Phase 2 can
    # authorise it through the DocumentReference that points at it.
    PUBLIC_TYPES = %w[Medication Practitioner Organization Location PractitionerRole].freeze

    attr_reader :patient_id

    def initialize(patient_id:, scope_set:)
      @patient_id = patient_id
      @scope_set = scope_set
    end

    # Base relation for searching `type`, or nil when this type is not confined
    # (callers then use their own default scope).
    def base_scope_for(type)
      return nil if PUBLIC_TYPES.include?(type)
      # The patient is in their own compartment, but holds no reference to
      # themselves, so PatientCompartment cannot express this one.
      return Patient.where(deleted: false, id: patient_id) if type == "Patient"

      PatientCompartment.scope_for_patient_id(type, patient_id)
    end

    def allows_record?(type, record)
      return true if PUBLIC_TYPES.include?(type)
      return record.id == patient_id if type == "Patient"

      PatientCompartment.member?(type, record, patient_id)
    end

    # Whether the granted scopes cover reading `type` at all. Needed where a
    # request pulls in resources the client never named -- _include and
    # $everything -- since the up-front scope check only saw the primary type.
    def readable_type?(type)
      @scope_set.allows?(type, :read)
    end
  end
end
