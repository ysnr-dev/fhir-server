# One Bulk Data $export job. Not part of Fhir::ResourceRegistry: this is
# server-generated job state, not a FHIR resource with its own REST
# interactions.
class BulkExport < ApplicationRecord
  # Export level, from the route that kicked the job off. `group` is the only
  # kind that reads group_id (the cohort whose members are exported).
  KINDS = %w[system patient group].freeze
  STATUSES = %w[in_progress completed failed cancelled].freeze
  STALE_AFTER = Integer(ENV.fetch("BULK_EXPORT_STALE_MINUTES", 60)).minutes

  has_many :bulk_export_files, dependent: :delete_all

  STATUSES.each do |value|
    define_method("#{value}?") { status == value }
  end

  # An in_progress export whose heartbeat (updated_at, touched per resource
  # type as it's generated) has gone quiet longer than STALE_AFTER almost
  # certainly died with the web dyno mid-job (no worker process survives a
  # deploy/restart on the free tier) rather than actually still running.
  def stale?
    in_progress? && updated_at < STALE_AFTER.ago
  end

  def mark_stale_failed!
    update!(status: "failed", error_message: "Export was interrupted, likely by a server restart. Re-issue the kick-off request.")
  end
end
