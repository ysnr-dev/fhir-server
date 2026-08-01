require "rails_helper"

RSpec.describe Device do
  def build_device(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts status, type, references, manufacturer, model, deviceName, and url" do
      device = build_device(
        "status" => "active",
        "type" => { "coding" => [{ "system" => "http://snomed.info/sct", "code" => "706172005" }] },
        "patient" => { "reference" => "Patient/p1" },
        "owner" => { "reference" => "Organization/o1" },
        "location" => { "reference" => "Location/l1" },
        "manufacturer" => "サンプル医療機器",
        "modelNumber" => "SM-100",
        "deviceName" => [
          { "name" => "サンプル人工呼吸器", "type" => "user-friendly-name" },
          { "name" => "SampleVent", "type" => "manufacturer-name" }
        ],
        "url" => "http://example.org/devices/DEV1"
      )

      device.sync_search_fields!

      expect(device.status).to eq("active")
      expect(device.type_code).to eq("706172005")
      expect(device.patient_reference).to eq("Patient/p1")
      expect(device.owner_reference).to eq("Organization/o1")
      expect(device.location_reference).to eq("Location/l1")
      expect(device.manufacturer).to eq("サンプル医療機器")
      expect(device.model_number).to eq("SM-100")
      # Every deviceName entry is joined so "device-name" can match any of them.
      expect(device.device_name_text).to eq("サンプル人工呼吸器 SampleVent")
      expect(device.url).to eq("http://example.org/devices/DEV1")
    end

    it "is nil-safe when fields are absent" do
      device = build_device({})

      expect { device.sync_search_fields! }.not_to raise_error
      expect(device.status).to be_nil
      expect(device.type_code).to be_nil
      expect(device.device_name_text).to be_nil
      expect(device.patient_reference).to be_nil
    end
  end

  describe "#sync_tokens!" do
    it "emits rows for status and every type coding" do
      device = build_device(
        "status" => "active",
        "type" => {
          "coding" => [
            { "system" => "http://snomed.info/sct", "code" => "706172005" },
            { "system" => "http://example.org/local", "code" => "VENT" }
          ]
        }
      )

      device.save!(validate: false)
      device.sync_tokens!

      expect(device.resource_tokens.where(param_name: "status").pluck(:code)).to eq(["active"])
      expect(device.resource_tokens.where(param_name: "type").pluck(:system, :code))
        .to contain_exactly(["http://snomed.info/sct", "706172005"], ["http://example.org/local", "VENT"])
    end
  end
end
