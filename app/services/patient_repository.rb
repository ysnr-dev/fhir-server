class PatientRepository
  class VersionConflict < StandardError
    attr_reader :current_version_id

    def initialize(current_version_id)
      @current_version_id = current_version_id
      super("If-Match version does not match current versionId #{current_version_id}")
    end
  end

  # id: is accepted (rather than always generated internally) so Bundle transaction
  # processing can pre-assign an id before resolving urn:uuid references across entries.
  def self.create(payload, id: SecureRandom.uuid)
    new.create(payload, id: id)
  end

  def self.update(patient, payload, if_match_version: nil)
    new.update(patient, payload, if_match_version: if_match_version)
  end

  def self.delete(patient)
    new.delete(patient)
  end

  def self.history(patient_id)
    PatientVersion.where(patient_id: patient_id).order(:version_id)
  end

  def self.version(patient_id, version_id)
    PatientVersion.find_by(patient_id: patient_id, version_id: version_id)
  end

  def create(payload, id:)
    now = Time.current
    resource = sanitize_resource(payload, id: id)

    ActiveRecord::Base.transaction do
      patient = Patient.new(
        id: id,
        version_id: 1,
        content: resource,
        deleted: false,
        last_updated: now
      )
      patient.sync_search_fields!
      patient.save!
      patient.sync_identifiers!

      PatientVersion.create!(
        patient_id: id,
        version_id: 1,
        content: resource,
        deleted: false,
        last_updated: now
      )

      patient
    end
  end

  def update(patient, payload, if_match_version: nil)
    patient.with_lock do
      if if_match_version.present? && if_match_version.to_i != patient.version_id
        raise VersionConflict, patient.version_id
      end

      now = Time.current
      new_version_id = patient.version_id + 1
      resource = sanitize_resource(payload, id: patient.id)

      patient.assign_attributes(
        content: resource,
        version_id: new_version_id,
        deleted: false,
        last_updated: now
      )
      patient.sync_search_fields!
      patient.save!
      patient.sync_identifiers!

      PatientVersion.create!(
        patient_id: patient.id,
        version_id: new_version_id,
        content: resource,
        deleted: false,
        last_updated: now
      )

      patient
    end
  end

  def delete(patient)
    patient.with_lock do
      return patient if patient.deleted?

      now = Time.current
      new_version_id = patient.version_id + 1

      patient.update!(deleted: true, version_id: new_version_id, last_updated: now)

      PatientVersion.create!(
        patient_id: patient.id,
        version_id: new_version_id,
        content: patient.content,
        deleted: true,
        last_updated: now
      )

      patient
    end
  end

  private

  # Strips client-supplied id/meta (server-assigned) and enforces resourceType.
  def sanitize_resource(payload, id:)
    resource = payload.deep_dup
    resource.delete("meta")
    resource["resourceType"] = "Patient"
    resource["id"] = id
    resource
  end
end
