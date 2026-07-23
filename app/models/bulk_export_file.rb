# One NDJSON output file (a single resource type, possibly one of several
# sequence-numbered parts when BulkExportGenerator splits large types).
class BulkExportFile < ApplicationRecord
  belongs_to :bulk_export
end
