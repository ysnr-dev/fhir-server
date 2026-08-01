module Fhir
  # Resolves a Group's members to the Patient logical ids that Group/$export
  # scopes to. Anything that is not a live Patient is dropped rather than
  # raising: a Group is a curated cohort that legitimately mixes member types,
  # and an export that failed because one member is a Practitioner would be
  # useless. Dangling Patient references cannot normally reach here at all --
  # GroupValidator rejects them at write time.
  module GroupMembers
    module_function

    # Skips members flagged `inactive: true` (no longer in the cohort),
    # non-Patient entities (they have no patient compartment to export), and
    # Patients that have since been deleted. `member.period` is deliberately not
    # evaluated: the Bulk Data IG defines no point-in-time cohort membership,
    # and `inactive` is the flag the spec provides for "no longer a member".
    def patient_ids(group)
      references = Array(group.content["member"]).filter_map do |member|
        next unless member.is_a?(Hash)
        next if member["inactive"] == true

        member.dig("entity", "reference")
      end

      ids = references.filter_map { |reference| reference[%r{\APatient/(.+)\z}, 1] }.uniq
      return [] if ids.empty?

      Patient.where(id: ids, deleted: false).pluck(:id)
    end
  end
end
