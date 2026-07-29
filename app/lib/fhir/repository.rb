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

    # One page of a type- or system-level history: newest versions first, with
    # the pre-paging total for Bundle.total and pagination links.
    HistoryPage = Struct.new(:versions, :total, :count, :offset, keyword_init: true)

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

      # Type-/system-level history are class methods (not instance ones like
      # #history) because system-level history spans every resource type and so
      # has no single registry entry to construct a Repository around.
      def type_history(resource_type, since: nil, count:, offset:)
        history_page(ResourceVersion.where(resource_type: resource_type), since: since, count: count, offset: offset)
      end

      def system_history(since: nil, count:, offset:)
        history_page(ResourceVersion.all, since: since, count: count, offset: offset)
      end

      private

      # `since` is inclusive ("at or after the given instant" per the spec).
      # The bigint PK breaks last_updated ties so paging order is stable.
      def history_page(scope, since:, count:, offset:)
        scope = scope.where("last_updated >= ?", since) if since

        HistoryPage.new(
          versions: scope.order(last_updated: :desc, id: :desc).limit(count).offset(offset),
          total: scope.count,
          count: count,
          offset: offset
        )
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
        record.sync_tokens!

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
        record.sync_tokens!

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

    # meta children the client owns and that therefore round-trip through a
    # write. Everything else in meta is server-assigned or registry-derived
    # (versionId, lastUpdated, profile) and is re-applied at render time by
    # Fhir::Meta, so persisting it would only let a stale copy drift.
    #
    # `tag` is here because it is the only meta child FHIR gives to the client
    # as authored content rather than as infrastructure -- JASPEHR, for one,
    # carries its submission (提出指定) and pseudonymization (仮名化指定) codes
    # on Questionnaire.meta.tag, and dropping them would silently discard part
    # of the resource. `security` deliberately stays out: labels that gate
    # access must not be settable by the writer.
    CLIENT_OWNED_META_KEYS = %w[tag].freeze

    # Strips client-supplied id and server-owned meta, and enforces resourceType.
    def sanitize_resource(payload, id:)
      resource = payload.deep_dup
      apply_meta_policy(resource)
      resource["resourceType"] = resource_type
      resource["id"] = id
      resource
    end

    def apply_meta_policy(resource)
      meta = resource["meta"]
      kept = meta.is_a?(Hash) ? meta.slice(*CLIENT_OWNED_META_KEYS).reject { |_k, v| v.blank? } : {}
      kept["tag"] = reject_subsetted(kept["tag"]) if kept.key?("tag")
      kept.reject! { |_k, v| v.blank? }

      if kept.empty?
        resource.delete("meta")
      else
        resource["meta"] = kept
      end
    end

    # SUBSETTED is stamped by Fhir::ResourceShaper on _summary/_elements results
    # to mark them incomplete. A client that round-trips such a result would
    # otherwise persist the marker onto a resource that is no longer partial.
    def reject_subsetted(tags)
      Array.wrap(tags).reject do |tag|
        tag.is_a?(Hash) &&
          tag["system"] == ResourceShaper::SUBSETTED_TAG["system"] &&
          tag["code"] == ResourceShaper::SUBSETTED_TAG["code"]
      end
    end
  end
end
