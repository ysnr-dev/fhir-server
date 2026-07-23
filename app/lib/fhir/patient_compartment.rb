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
      entry = ResourceRegistry.entry_for(type)
      columns = reference_columns_for(type)
      return entry[:model].none if columns.empty?

      reference = "Patient/#{patient.id}"
      entry[:model].where(deleted: false)
                   .where(columns.map { |column| "#{column} = ?" }.join(" OR "), *([reference] * columns.size))
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
