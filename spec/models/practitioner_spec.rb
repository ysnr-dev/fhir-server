require "rails_helper"

RSpec.describe Practitioner do
  def build_practitioner(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts gender, active, and birth_date" do
      practitioner = build_practitioner("gender" => "female", "active" => true, "birthDate" => "1985-03-20")

      practitioner.sync_search_fields!

      expect(practitioner.gender).to eq("female")
      expect(practitioner.active).to eq(true)
      expect(practitioner.birth_date).to eq(Date.new(1985, 3, 20))
    end

    it "extracts the official family/given name and combined name_text" do
      practitioner = build_practitioner(
        "name" => [
          { "use" => "official", "family" => "鈴木", "given" => ["一郎"] },
          { "family" => "スズキ", "given" => ["イチロウ"] }
        ]
      )

      practitioner.sync_search_fields!

      expect(practitioner.family).to eq("鈴木")
      expect(practitioner.given).to eq("一郎")
      expect(practitioner.name_text).to include("鈴木", "一郎", "スズキ", "イチロウ")
    end

    it "is nil-safe when all fields are absent" do
      practitioner = build_practitioner({})

      expect { practitioner.sync_search_fields! }.not_to raise_error
      expect(practitioner.birth_date).to be_nil
      expect(practitioner.family).to be_nil
    end
  end
end
