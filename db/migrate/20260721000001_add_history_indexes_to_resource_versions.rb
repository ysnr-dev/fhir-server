# Type-/system-level history (GET /{type}/_history, GET /_history) orders and
# filters resource_versions by last_updated, which the original unique
# [resource_type, resource_id, version_id] index cannot serve.
class AddHistoryIndexesToResourceVersions < ActiveRecord::Migration[7.0]
  def change
    add_index :resource_versions, %i[resource_type last_updated]
    add_index :resource_versions, :last_updated
  end
end
