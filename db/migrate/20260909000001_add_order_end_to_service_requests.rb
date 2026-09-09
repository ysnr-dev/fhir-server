# オーダーの終了日(fhir-client のローカル拡張 *-order-end)を索引する列。
# 看護指示・食事・リハビリ・栄養指導のような継続的な指示は、開始を occurrenceDateTime、
# 終了をこの拡張で持つ。これまで上流で終了を絞れず、クライアントは「基準日以前に始まった
# 有効なオーダーを全部読んでから終わったものを捨てる」作りになっていた。
# order-period 検索パラメータ(開始 = occurrence_date_time、終了 = order_end)の end_column。
class AddOrderEndToServiceRequests < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill never depends on the real ServiceRequest model.
  class MigrationServiceRequest < ActiveRecord::Base
    self.table_name = "service_requests"
  end

  ORDER_END_EXTENSION_URLS = %w[
    http://fhir-client.local/StructureDefinition/nursing-order-end
    http://fhir-client.local/StructureDefinition/meal-order-end
    http://fhir-client.local/StructureDefinition/rehab-order-end
    http://fhir-client.local/StructureDefinition/nutrition-guidance-order-end
  ].freeze

  def up
    add_column :service_requests, :order_end, :datetime
    add_index :service_requests, :order_end

    MigrationServiceRequest.reset_column_information
    backfill_order_end
  end

  def down
    remove_column :service_requests, :order_end
  end

  private

  # 無料枠は RAM 512MB なので、小さめのバッチで回す。対象は拡張を持つ行だけ
  # (jsonb 包含で GIN 索引が効く)。
  def backfill_order_end
    ORDER_END_EXTENSION_URLS.each do |url|
      MigrationServiceRequest
        .where("content @> ?::jsonb", { extension: [{ url: url }] }.to_json)
        .find_each(batch_size: 200) do |request|
          time = order_end_of(request.content)
          request.update_column(:order_end, time) if time
        end
    end
  end

  def order_end_of(content)
    extension = Array(content["extension"]).find do |element|
      element.is_a?(Hash) && ORDER_END_EXTENSION_URLS.include?(element["url"])
    end
    return nil unless extension

    parse_time(extension["valueDateTime"] || extension["valueDate"] || extension["valueInstant"])
  end

  # Fhir::FieldExtractor.datetime と同じ規則: 日付だけの値は UTC 0 時として持つ
  # (検索側も日付精度の値を UTC の日区間に展開して比べる)。
  def parse_time(value)
    return nil if value.blank?

    Time.iso8601(value)
  rescue ArgumentError, TypeError
    begin
      Date.iso8601(value).to_time(:utc)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
