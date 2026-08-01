module Fhir
  # Patient-compartment membership: which registered resource types reference
  # a Patient, and how to scope their records either to one patient (used by
  # Patient/:id/$everything) or to every patient at once (used by the
  # system-wide Patient/$export, which exports all compartments in a single
  # pass rather than one at a time).
  module PatientCompartment
    module_function

    # Reference-typed search param columns on `type` that target Patient
    # (single-valued only; no multiple:true Patient reference exists in the
    # current registry, so compartment membership is always a plain indexed
    # column match).
    def reference_columns_for(type)
      entry = ResourceRegistry.entry_for(type)
      entry[:search_params].values
                           .select { |definition| definition[:type] == :reference && definition[:target_type] == "Patient" && !definition[:multiple] }
                           .map { |definition| definition[:column] }
                           .uniq
    end

    # Scope of `type`'s (non-deleted) records that belong to `patient`'s
    # compartment. Empty relation when `type` has no Patient-targeting column.
    def scope_for_patient(type, patient)
      scope_for_patient_id(type, patient.id)
    end

    # Same, addressed by logical id. Access control (Fhir::PatientContext) works
    # from the id on the token and never needs to load the Patient row.
    def scope_for_patient_id(type, patient_id)
      scope_for_patient_ids(type, [patient_id])
    end

    # Scope of `type`'s (non-deleted) records belonging to ANY of these patients'
    # compartments -- Group/$export exports a whole cohort in one pass rather
    # than one compartment at a time. An empty id list matches nothing.
    def scope_for_patient_ids(type, patient_ids)
      entry = ResourceRegistry.entry_for(type)
      columns = reference_columns_for(type)
      return entry[:model].none if columns.empty? || patient_ids.empty?

      references = patient_ids.map { |patient_id| "Patient/#{patient_id}" }
      entry[:model].where(deleted: false)
                   .where(columns.map { |column| "#{column} IN (?)" }.join(" OR "), *([references] * columns.size))
    end

    # Whether an already-loaded record sits in `patient_id`'s compartment.
    # False for types with no Patient-targeting column: membership cannot be
    # established, so it is not granted.
    def member?(type, record, patient_id)
      reference = "Patient/#{patient_id}"
      reference_columns_for(type).any? { |column| record[column] == reference }
    end

    # Scope of `type`'s (non-deleted) records that belong to ANY patient's
    # compartment (any Patient-targeting column is populated).
    def scope_for_any_patient(type)
      entry = ResourceRegistry.entry_for(type)
      columns = reference_columns_for(type)
      return entry[:model].none if columns.empty?

      entry[:model].where(deleted: false)
                   .where(columns.map { |column| "#{column} IS NOT NULL" }.join(" OR "))
    end
  end
end
