class ServiceRequestRepository
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

  def self.update(service_request, payload, if_match_version: nil)
    new.update(service_request, payload, if_match_version: if_match_version)
  end

  def self.delete(service_request)
    new.delete(service_request)
  end

  def self.history(service_request_id)
    ServiceRequestVersion.where(service_request_id: service_request_id).order(:version_id)
  end

  def self.version(service_request_id, version_id)
    ServiceRequestVersion.find_by(service_request_id: service_request_id, version_id: version_id)
  end

  def create(payload, id:)
    now = Time.current
    resource = sanitize_resource(payload, id: id)

    ActiveRecord::Base.transaction do
      service_request = ServiceRequest.new(
        id: id,
        version_id: 1,
        content: resource,
        deleted: false,
        last_updated: now
      )
      service_request.sync_search_fields!
      service_request.save!
      service_request.sync_identifiers!

      ServiceRequestVersion.create!(
        service_request_id: id,
        version_id: 1,
        content: resource,
        deleted: false,
        last_updated: now
      )

      service_request
    end
  end

  def update(service_request, payload, if_match_version: nil)
    service_request.with_lock do
      if if_match_version.present? && if_match_version.to_i != service_request.version_id
        raise VersionConflict, service_request.version_id
      end

      now = Time.current
      new_version_id = service_request.version_id + 1
      resource = sanitize_resource(payload, id: service_request.id)

      service_request.assign_attributes(
        content: resource,
        version_id: new_version_id,
        deleted: false,
        last_updated: now
      )
      service_request.sync_search_fields!
      service_request.save!
      service_request.sync_identifiers!

      ServiceRequestVersion.create!(
        service_request_id: service_request.id,
        version_id: new_version_id,
        content: resource,
        deleted: false,
        last_updated: now
      )

      service_request
    end
  end

  def delete(service_request)
    service_request.with_lock do
      return service_request if service_request.deleted?

      now = Time.current
      new_version_id = service_request.version_id + 1

      service_request.update!(deleted: true, version_id: new_version_id, last_updated: now)

      ServiceRequestVersion.create!(
        service_request_id: service_request.id,
        version_id: new_version_id,
        content: service_request.content,
        deleted: true,
        last_updated: now
      )

      service_request
    end
  end

  private

  # Strips client-supplied id/meta (server-assigned) and enforces resourceType.
  def sanitize_resource(payload, id:)
    resource = payload.deep_dup
    resource.delete("meta")
    resource["resourceType"] = "ServiceRequest"
    resource["id"] = id
    resource
  end
end
