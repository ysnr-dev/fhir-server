# Patient を住所(address)と電話番号(phone)で検索できるようにする。抽出列は書き込み時に
# しか埋まらないので、既存の患者はここで content から起こす(本番には Shell が無い)。
class AddAddressAndPhoneToPatients < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill never depends on the real Patient model.
  class MigrationPatient < ActiveRecord::Base
    self.table_name = "patients"
  end

  def up
    add_column :patients, :address_text, :string
    add_column :patients, :phone_digits, :string

    MigrationPatient.reset_column_information
    backfill
  end

  def down
    remove_column :patients, :phone_digits
    remove_column :patients, :address_text
  end

  private

  # 無料枠は RAM 512MB なので、小さめのバッチで回す。
  def backfill
    MigrationPatient
      .where("content ? 'address' OR content ? 'telecom'")
      .find_each(batch_size: 200) do |patient|
        patient.update_columns(
          address_text: address_list_text(patient.content["address"]),
          phone_digits: phone_digits(patient.content["telecom"])
        )
      end
  end

  # Fhir::FieldExtractor.address_list_text と同じ規則。
  def address_list_text(addresses)
    Array.wrap(addresses).filter_map do |address|
      next unless address.is_a?(Hash)

      [address["text"], *Array(address["line"]), address["city"], address["state"], address["postalCode"]]
        .compact.join(" ").presence
    end.join(" ").presence
  end

  # Fhir::FieldExtractor.phone_digits と同じ規則。
  def phone_digits(telecoms)
    Array.wrap(telecoms).filter_map do |telecom|
      next unless telecom.is_a?(Hash) && telecom["system"] == "phone"

      telecom["value"].to_s.tr("０-９", "0-9").gsub(/\D/, "").presence
    end.join(" ").presence
  end
end
