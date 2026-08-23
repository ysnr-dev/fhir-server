class AddOccurrenceDateTimeToServiceRequests < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill survives future changes to the real
  # ServiceRequest model/class (e.g. new validations, callbacks).
  class MigrationServiceRequest < ActiveRecord::Base
    self.table_name = "service_requests"
  end

  def up
    add_column :service_requests, :occurrence_date_time, :datetime
    add_index :service_requests, :occurrence_date_time

    MigrationServiceRequest.reset_column_information
    backfill_occurrence
  end

  def down
    remove_column :service_requests, :occurrence_date_time
  end

  private

  # 無料枠は RAM 512MB なので、jsonb の content を抱え込みすぎないよう
  # 小さめのバッチで回す。
  def backfill_occurrence
    MigrationServiceRequest.where("content ? 'occurrenceDateTime'").find_each(batch_size: 200) do |request|
      time = parse_time(request.content["occurrenceDateTime"])
      request.update_column(:occurrence_date_time, time) if time
    end
  end

  # Mirrors Fhir::FieldExtractor.datetime (full ISO8601, else partial date as
  # UTC midnight) without depending on app code from a migration.
  def parse_time(value)
    return nil if value.blank?

    Time.iso8601(value)
  rescue ArgumentError, TypeError
    parse_partial_date(value)&.to_time(:utc)
  end

  def parse_partial_date(value)
    return nil unless value.is_a?(String)

    Date.iso8601(value)
  rescue ArgumentError
    begin
      Date.strptime(value, "%Y-%m")
    rescue ArgumentError
      begin
        Date.strptime(value, "%Y")
      rescue ArgumentError
        nil
      end
    end
  end
end
