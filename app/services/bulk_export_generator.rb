# Streams every requested resource type into NDJSON, split across
# BulkExportFile rows so no single row (or the export as a whole) grows
# without bound -- Neon's free-tier storage and the web dyno's memory are both
# limited. Runs inside BulkExportJob.
class BulkExportGenerator
  class TooLarge < StandardError; end

  MAX_FILE_BYTES = Integer(ENV.fetch("BULK_EXPORT_MAX_FILE_BYTES", 10 * 1024 * 1024))
  MAX_TOTAL_BYTES = Integer(ENV.fetch("BULK_EXPORT_MAX_TOTAL_BYTES", 50 * 1024 * 1024))

  def self.call(export)
    new(export).call
  end

  def initialize(export)
    @export = export
    @total_bytes = 0
  end

  def call
    types_for.each do |type|
      return if export.reload.cancelled?

      generate_type(type)
      export.touch # heartbeat -- lets BulkExport#stale? tell a dead job from a slow one
    end
  end

  private

  attr_reader :export

  # System-level export: every requested type, unfiltered by compartment.
  # Patient-level export: the Patient resources themselves (always included,
  # like Patient/:id/$everything's subject) plus every requested type scoped
  # to any patient's compartment.
  def types_for
    if export.kind == "system"
      export.types || Fhir::ResourceRegistry.types
    else
      compartment_types = export.types || (Fhir::ResourceRegistry.types - ["Patient"])
      (["Patient"] + compartment_types).uniq
    end
  end

  def scope_for(type)
    base =
      if export.kind == "patient" && type != "Patient"
        Fhir::PatientCompartment.scope_for_any_patient(type)
      else
        Fhir::ResourceRegistry.entry_for(type).fetch(:model).where(deleted: false)
      end

    base = base.where("last_updated >= ?", export.since) if export.since
    base.where("last_updated <= ?", export.transaction_time).order(:id)
  end

  def generate_type(type)
    sequence = 1
    buffer = +""
    count = 0

    scope_for(type).find_each(batch_size: 200) do |record|
      buffer << JSON.generate(Fhir::Meta.apply(record.content, version_id: record.version_id, last_updated: record.last_updated))
      buffer << "\n"
      count += 1

      next unless buffer.bytesize >= MAX_FILE_BYTES

      flush(type, sequence, buffer, count)
      sequence += 1
      buffer = +""
      count = 0
    end

    flush(type, sequence, buffer, count) if count.positive?
  end

  # Zero-count types are omitted entirely -- the IG says empty output entries
  # should not be listed in the completion manifest.
  def flush(type, sequence, buffer, count)
    @total_bytes += buffer.bytesize
    if @total_bytes > MAX_TOTAL_BYTES
      raise TooLarge, "Export exceeded #{MAX_TOTAL_BYTES} bytes; narrow _type or _since and retry"
    end

    export.bulk_export_files.create!(
      id: SecureRandom.uuid,
      resource_type: type,
      sequence: sequence,
      content: buffer,
      resource_count: count,
      byte_size: buffer.bytesize
    )
  end
end
