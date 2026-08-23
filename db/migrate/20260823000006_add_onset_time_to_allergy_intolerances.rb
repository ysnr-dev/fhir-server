class AddOnsetTimeToAllergyIntolerances < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill never depends on the real model.
  class MigrationAllergyIntolerance < ActiveRecord::Base
    self.table_name = "allergy_intolerances"
  end

  def up
    add_column :allergy_intolerances, :onset_time, :datetime
    add_index :allergy_intolerances, :onset_time

    MigrationAllergyIntolerance.reset_column_information
    backfill_onset_time
  end

  def down
    remove_column :allergy_intolerances, :onset_time
  end

  private

  # 無料枠は RAM 512MB なので、小さめのバッチで回す。
  def backfill_onset_time
    MigrationAllergyIntolerance.where("content ? 'onsetDateTime'").find_each(batch_size: 200) do |allergy|
      time = parse_time(allergy.content["onsetDateTime"])
      allergy.update_column(:onset_time, time) if time
    end
  end

  # Fhir::FieldExtractor.datetime と同じ(完全な ISO8601、駄目なら日付を UTC 0 時)。
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
