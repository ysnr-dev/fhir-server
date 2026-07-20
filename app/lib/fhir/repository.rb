module Fhir
  # Persists a single resource type's records/versions/identifiers, parameterized by
  # resource_type via Fhir::ResourceRegistry so every FHIR resource shares one
  # implementation instead of a hand-written repository per type.
  class Repository
    class VersionConflict < StandardError
      attr_reader :current_version_id

      def initialize(current_version_id)
        @current_version_id = current_version_id
        super("If-Match version does not match current versionId #{current_version_id}")
      end
    end

    class << self
      # id: is accepted (rather than always generated internally) so Bundle transaction
      # processing can pre-assign an id before resolving urn:uuid references across entries.
      def create(resource_type, payload, id: SecureRandom.uuid)
        new(resource_type).create(payload, id: id)
      end

      def update(resource_type, record, payload, if_match_version: nil)
        new(resource_type).update(record, payload, if_match_version: if_match_version)
      end

      def delete(resource_type, record)
        new(resource_type).delete(record)
      end

      def history(resource_type, resource_id)
        new(resource_type).history(resource_id)
      end

      def version(resource_type, resource_id, version_id)
        new(resource_type).version(resource_id, version_id)
      end
    end

    def initialize(resource_type)
      @resource_type = resource_type
      @model = ResourceRegistry.entry_for(resource_type).fetch(:model)
    end

    def create(payload, id: SecureRandom.uuid)
      now = Time.current
      resource = sanitize_resource(payload, id: id)

      ActiveRecord::Base.transaction do
        record = model.new(
          id: id,
          version_id: 1,
          content: resource,
          deleted: false,
          last_updated: now
        )
        record.sync_search_fields!
        record.save!
        record.sync_identifiers!

        ResourceVersion.create!(
          resource_type: resource_type,
          resource_id: id,
          version_id: 1,
          content: resource,
          deleted: false,
          last_updated: now
        )

        record
      end
    end

    def update(record, payload, if_match_version: nil)
      record.with_lock do
        if if_match_version.present? && if_match_version.to_i != record.version_id
          raise VersionConflict, record.version_id
        end

        now = Time.current
        new_version_id = record.version_id + 1
        resource = sanitize_resource(payload, id: record.id)

        record.assign_attributes(
          content: resource,
          version_id: new_version_id,
          deleted: false,
          last_updated: now
        )
        record.sync_search_fields!
        record.save!
        record.sync_identifiers!

        ResourceVersion.create!(
          resource_type: resource_type,
          resource_id: record.id,
          version_id: new_version_id,
          content: resource,
          deleted: false,
          last_updated: now
        )

        record
      end
    end

    def delete(record)
      record.with_lock do
        return record if record.deleted?

        now = Time.current
        new_version_id = record.version_id + 1

        record.update!(deleted: true, version_id: new_version_id, last_updated: now)

        ResourceVersion.create!(
          resource_type: resource_type,
          resource_id: record.id,
          version_id: new_version_id,
          content: record.content,
          deleted: true,
          last_updated: now
        )

        record
      end
    end

    def history(resource_id)
      ResourceVersion.where(resource_type: resource_type, resource_id: resource_id).order(:version_id)
    end

    def version(resource_id, version_id)
      ResourceVersion.find_by(resource_type: resource_type, resource_id: resource_id, version_id: version_id)
    end

    private

    attr_reader :resource_type, :model

    # Strips client-supplied id/meta (server-assigned) and enforces resourceType.
    def sanitize_resource(payload, id:)
      resource = payload.deep_dup
      resource.delete("meta")
      resource["resourceType"] = resource_type
      resource["id"] = id
      resource
    end
  end
end
