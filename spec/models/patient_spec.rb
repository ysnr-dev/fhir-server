require "rails_helper"

RSpec.describe Patient do
  def build_patient(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts gender, active, and birth_date" do
      patient = build_patient("gender" => "female", "active" => true, "birthDate" => "1985-03-20")

      patient.sync_search_fields!

      expect(patient.gender).to eq("female")
      expect(patient.active).to eq(true)
      expect(patient.birth_date).to eq(Date.new(1985, 3, 20))
    end

    it "parses a year-only birthDate" do
      patient = build_patient("birthDate" => "1985")

      patient.sync_search_fields!

      expect(patient.birth_date).to eq(Date.new(1985, 1, 1))
    end

    it "parses a year-month birthDate" do
      patient = build_patient("birthDate" => "1985-03")

      patient.sync_search_fields!

      expect(patient.birth_date).to eq(Date.new(1985, 3, 1))
    end

    it "extracts the official family/given name and combined name_text" do
      patient = build_patient(
        "name" => [
          { "use" => "official", "family" => "山田", "given" => ["太郎"] },
          { "family" => "ヤマダ", "given" => ["タロウ"] }
        ]
      )

      patient.sync_search_fields!

      expect(patient.family).to eq("山田")
      expect(patient.given).to eq("太郎")
      expect(patient.name_text).to include("山田", "太郎", "ヤマダ", "タロウ")
    end

    it "is nil-safe when name and birthDate are absent" do
      patient = build_patient({})

      expect { patient.sync_search_fields! }.not_to raise_error
      expect(patient.birth_date).to be_nil
      expect(patient.family).to be_nil
    end
  end
end
