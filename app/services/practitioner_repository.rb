class PractitionerRepository
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

  def self.update(practitioner, payload, if_match_version: nil)
    new.update(practitioner, payload, if_match_version: if_match_version)
  end

  def self.delete(practitioner)
    new.delete(practitioner)
  end

  def self.history(practitioner_id)
    PractitionerVersion.where(practitioner_id: practitioner_id).order(:version_id)
  end

  def self.version(practitioner_id, version_id)
    PractitionerVersion.find_by(practitioner_id: practitioner_id, version_id: version_id)
  end

  def create(payload, id:)
    now = Time.current
    resource = sanitize_resource(payload, id: id)

    ActiveRecord::Base.transaction do
      practitioner = Practitioner.new(
        id: id,
        version_id: 1,
        content: resource,
        deleted: false,
        last_updated: now
      )
      practitioner.sync_search_fields!
      practitioner.save!
      practitioner.sync_identifiers!

      PractitionerVersion.create!(
        practitioner_id: id,
        version_id: 1,
        content: resource,
        deleted: false,
        last_updated: now
      )

      practitioner
    end
  end

  def update(practitioner, payload, if_match_version: nil)
    practitioner.with_lock do
      if if_match_version.present? && if_match_version.to_i != practitioner.version_id
        raise VersionConflict, practitioner.version_id
      end

      now = Time.current
      new_version_id = practitioner.version_id + 1
      resource = sanitize_resource(payload, id: practitioner.id)

      practitioner.assign_attributes(
        content: resource,
        version_id: new_version_id,
        deleted: false,
        last_updated: now
      )
      practitioner.sync_search_fields!
      practitioner.save!
      practitioner.sync_identifiers!

      PractitionerVersion.create!(
        practitioner_id: practitioner.id,
        version_id: new_version_id,
        content: resource,
        deleted: false,
        last_updated: now
      )

      practitioner
    end
  end

  def delete(practitioner)
    practitioner.with_lock do
      return practitioner if practitioner.deleted?

      now = Time.current
      new_version_id = practitioner.version_id + 1

      practitioner.update!(deleted: true, version_id: new_version_id, last_updated: now)

      PractitionerVersion.create!(
        practitioner_id: practitioner.id,
        version_id: new_version_id,
        content: practitioner.content,
        deleted: true,
        last_updated: now
      )

      practitioner
    end
  end

  private

  # Strips client-supplied id/meta (server-assigned) and enforces resourceType.
  def sanitize_resource(payload, id:)
    resource = payload.deep_dup
    resource.delete("meta")
    resource["resourceType"] = "Practitioner"
    resource["id"] = id
    resource
  end
end
