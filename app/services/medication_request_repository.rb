class MedicationRequestRepository
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

  def self.update(medication_request, payload, if_match_version: nil)
    new.update(medication_request, payload, if_match_version: if_match_version)
  end

  def self.delete(medication_request)
    new.delete(medication_request)
  end

  def self.history(medication_request_id)
    MedicationRequestVersion.where(medication_request_id: medication_request_id).order(:version_id)
  end

  def self.version(medication_request_id, version_id)
    MedicationRequestVersion.find_by(medication_request_id: medication_request_id, version_id: version_id)
  end

  def create(payload, id:)
    now = Time.current
    resource = sanitize_resource(payload, id: id)

    ActiveRecord::Base.transaction do
      medication_request = MedicationRequest.new(
        id: id,
        version_id: 1,
        content: resource,
        deleted: false,
        last_updated: now
      )
      medication_request.sync_search_fields!
      medication_request.save!
      medication_request.sync_identifiers!

      MedicationRequestVersion.create!(
        medication_request_id: id,
        version_id: 1,
        content: resource,
        deleted: false,
        last_updated: now
      )

      medication_request
    end
  end

  def update(medication_request, payload, if_match_version: nil)
    medication_request.with_lock do
      if if_match_version.present? && if_match_version.to_i != medication_request.version_id
        raise VersionConflict, medication_request.version_id
      end

      now = Time.current
      new_version_id = medication_request.version_id + 1
      resource = sanitize_resource(payload, id: medication_request.id)

      medication_request.assign_attributes(
        content: resource,
        version_id: new_version_id,
        deleted: false,
        last_updated: now
      )
      medication_request.sync_search_fields!
      medication_request.save!
      medication_request.sync_identifiers!

      MedicationRequestVersion.create!(
        medication_request_id: medication_request.id,
        version_id: new_version_id,
        content: resource,
        deleted: false,
        last_updated: now
      )

      medication_request
    end
  end

  def delete(medication_request)
    medication_request.with_lock do
      return medication_request if medication_request.deleted?

      now = Time.current
      new_version_id = medication_request.version_id + 1

      medication_request.update!(deleted: true, version_id: new_version_id, last_updated: now)

      MedicationRequestVersion.create!(
        medication_request_id: medication_request.id,
        version_id: new_version_id,
        content: medication_request.content,
        deleted: true,
        last_updated: now
      )

      medication_request
    end
  end

  private

  # Strips client-supplied id/meta (server-assigned) and enforces resourceType.
  def sanitize_resource(payload, id:)
    resource = payload.deep_dup
    resource.delete("meta")
    resource["resourceType"] = "MedicationRequest"
    resource["id"] = id
    resource
  end
end
