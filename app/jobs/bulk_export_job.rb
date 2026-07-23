# Runs a Bulk Data $export in the background via ActiveJob's default :async
# adapter (an in-process thread pool -- there is no separate worker dyno on
# the Render free tier). If the process restarts mid-job the export is left
# "in_progress" with a stale heartbeat; BulkExport#stale? and the
# fhir:purge_bulk_exports rake task both fail it out rather than leaving
# pollers waiting forever.
class BulkExportJob < ApplicationJob
  queue_as :default

  def perform(export_id)
    export = BulkExport.find_by(id: export_id)
    return unless export&.in_progress?

    BulkExportGenerator.call(export)
    export.reload
    export.update!(status: "completed") if export.in_progress?
  rescue StandardError => e
    Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
    Rails.logger.error("BulkExportJob failed for #{export_id}: #{e.class}: #{e.message}")
    export&.update!(status: "failed", error_message: e.message)
  end
end
