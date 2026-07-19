class OrganizationRepository
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

  def self.update(organization, payload, if_match_version: nil)
    new.update(organization, payload, if_match_version: if_match_version)
  end

  def self.delete(organization)
    new.delete(organization)
  end

  def self.history(organization_id)
    OrganizationVersion.where(organization_id: organization_id).order(:version_id)
  end

  def self.version(organization_id, version_id)
    OrganizationVersion.find_by(organization_id: organization_id, version_id: version_id)
  end

  def create(payload, id:)
    now = Time.current
    resource = sanitize_resource(payload, id: id)

    ActiveRecord::Base.transaction do
      organization = Organization.new(
        id: id,
        version_id: 1,
        content: resource,
        deleted: false,
        last_updated: now
      )
      organization.sync_search_fields!
      organization.save!
      organization.sync_identifiers!

      OrganizationVersion.create!(
        organization_id: id,
        version_id: 1,
        content: resource,
        deleted: false,
        last_updated: now
      )

      organization
    end
  end

  def update(organization, payload, if_match_version: nil)
    organization.with_lock do
      if if_match_version.present? && if_match_version.to_i != organization.version_id
        raise VersionConflict, organization.version_id
      end

      now = Time.current
      new_version_id = organization.version_id + 1
      resource = sanitize_resource(payload, id: organization.id)

      organization.assign_attributes(
        content: resource,
        version_id: new_version_id,
        deleted: false,
        last_updated: now
      )
      organization.sync_search_fields!
      organization.save!
      organization.sync_identifiers!

      OrganizationVersion.create!(
        organization_id: organization.id,
        version_id: new_version_id,
        content: resource,
        deleted: false,
        last_updated: now
      )

      organization
    end
  end

  def delete(organization)
    organization.with_lock do
      return organization if organization.deleted?

      now = Time.current
      new_version_id = organization.version_id + 1

      organization.update!(deleted: true, version_id: new_version_id, last_updated: now)

      OrganizationVersion.create!(
        organization_id: organization.id,
        version_id: new_version_id,
        content: organization.content,
        deleted: true,
        last_updated: now
      )

      organization
    end
  end

  private

  # Strips client-supplied id/meta (server-assigned) and enforces resourceType.
  def sanitize_resource(payload, id:)
    resource = payload.deep_dup
    resource.delete("meta")
    resource["resourceType"] = "Organization"
    resource["id"] = id
    resource
  end
end
