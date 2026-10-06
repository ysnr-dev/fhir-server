# MedicationAdministration をロット番号(lot-number)で検索できるようにする。抽出列は書き込み時に
# しか埋まらないので、既存の投与(輸血の製剤番号)はここで content から起こす(本番には Shell が無い)。
class AddLotNumberToMedicationAdministrations < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill never depends on the real model.
  class MigrationMedicationAdministration < ActiveRecord::Base
    self.table_name = "medication_administrations"
  end

  # Fhir::ExtractionDefinitions::MedicationAdministration::LOT_NUMBER_EXTENSION_URLS と同じ。
  LOT_NUMBER_EXTENSION_URLS = %w[
    http://fhir-client.local/StructureDefinition/medication-lot-number
    http://fhir-client.local/StructureDefinition/transfusion-lot-number
  ].freeze

  def up
    add_column :medication_administrations, :lot_number, :string
    add_index :medication_administrations, :lot_number

    MigrationMedicationAdministration.reset_column_information
    backfill
  end

  def down
    remove_index :medication_administrations, :lot_number
    remove_column :medication_administrations, :lot_number
  end

  private

  # 無料枠は RAM 512MB なので、小さめのバッチで回す。
  def backfill
    MigrationMedicationAdministration
      .where("content ? 'extension'")
      .find_each(batch_size: 200) do |record|
        lot = lot_number(record.content["extension"])
        record.update_columns(lot_number: lot) if lot
      end
  end

  # Fhir::FieldExtractor.extension_string と同じ規則。
  def lot_number(extensions)
    extension = Array(extensions).find do |element|
      element.is_a?(Hash) && LOT_NUMBER_EXTENSION_URLS.include?(element["url"])
    end
    extension && extension["valueString"].presence
  end
end
