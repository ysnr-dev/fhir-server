require "rails_helper"

RSpec.describe ServiceRequest do
  def build_service_request(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, intent, subject_reference, and authored_on" do
      service_request = build_service_request(
        "status" => "active",
        "intent" => "order",
        "subject" => { "reference" => "Patient/abc123" },
        "authoredOn" => "2026-07-19T10:00:00+09:00"
      )

      service_request.sync_search_fields!

      expect(service_request.status).to eq("active")
      expect(service_request.intent).to eq("order")
      expect(service_request.subject_reference).to eq("Patient/abc123")
      expect(service_request.authored_on).to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
    end

    it "extracts code and code_text from the code CodeableConcept" do
      service_request = build_service_request(
        "code" => {
          "coding" => [{ "system" => "http://snomed.info/sct", "code" => "396550006", "display" => "血液検査" }],
          "text" => "血液検査"
        }
      )

      service_request.sync_search_fields!

      expect(service_request.code).to eq("396550006")
      expect(service_request.code_text).to include("血液検査")
    end

    it "is nil-safe when fields are absent" do
      service_request = build_service_request({})

      expect { service_request.sync_search_fields! }.not_to raise_error
      expect(service_request.authored_on).to be_nil
      expect(service_request.code).to be_nil
      expect(service_request.subject_reference).to be_nil
    end
  end
end
