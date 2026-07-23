require "rails_helper"

RSpec.describe BulkExportJob do
  def build_export
    BulkExport.create!(
      id: SecureRandom.uuid, kind: "system", status: "in_progress",
      output_format: "application/fhir+ndjson", transaction_time: Time.current,
      request_url: "http://example.test/$export"
    )
  end

  it "marks the export completed after generation succeeds" do
    export = build_export

    described_class.perform_now(export.id)

    expect(export.reload.status).to eq("completed")
  end

  it "marks the export failed and records the error message when generation raises" do
    export = build_export
    allow(BulkExportGenerator).to receive(:call).and_raise(StandardError, "boom")

    described_class.perform_now(export.id)

    expect(export.reload.status).to eq("failed")
    expect(export.error_message).to eq("boom")
  end

  it "leaves a cancelled export's status untouched" do
    export = build_export
    allow(BulkExportGenerator).to receive(:call) { export.update!(status: "cancelled") }

    described_class.perform_now(export.id)

    expect(export.reload.status).to eq("cancelled")
  end

  it "is a no-op for an export that is no longer in_progress" do
    export = build_export
    export.update!(status: "cancelled")

    expect(BulkExportGenerator).not_to receive(:call)
    described_class.perform_now(export.id)
  end
end
