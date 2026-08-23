class AddIdentifierValueToOrganizations < ActiveRecord::Migration[7.0]
  # Table-scoped stub so the backfill survives future changes to the real
  # Organization model/class.
  class MigrationOrganization < ActiveRecord::Base
    self.table_name = "organizations"
  end

  def up
    add_column :organizations, :identifier_value, :string
    add_index :organizations, :identifier_value

    MigrationOrganization.reset_column_information
    backfill_identifier_value
  end

  def down
    remove_column :organizations, :identifier_value
  end

  private

  # First identifier's value, mirroring Fhir::FieldExtractor.first_identifier_value.
  # The column only serves _sort=identifier; matching still goes through
  # resource_identifiers.
  def backfill_identifier_value
    MigrationOrganization.where("content ? 'identifier'").find_each(batch_size: 200) do |organization|
      value = Array(organization.content["identifier"])
              .filter_map { |i| i.is_a?(Hash) ? i["value"].presence : nil }
              .first
      organization.update_column(:identifier_value, value) if value
    end
  end
end
