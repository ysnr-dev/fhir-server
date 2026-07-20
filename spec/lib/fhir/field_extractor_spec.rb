require "rails_helper"

RSpec.describe Fhir::FieldExtractor do
  describe ".dig_path" do
    let(:resource) { { "subject" => { "reference" => "Patient/1" }, "active" => true } }

    it "returns a top-level value" do
      expect(described_class.dig_path(resource, "active")).to be(true)
    end

    it "digs a dotted path" do
      expect(described_class.dig_path(resource, "subject.reference")).to eq("Patient/1")
    end

    it "is nil-safe on a missing intermediate node" do
      expect(described_class.dig_path(resource, "encounter.reference")).to be_nil
    end

    it "is nil-safe when a step is a non-hash" do
      expect(described_class.dig_path({ "a" => "scalar" }, "a.b")).to be_nil
    end
  end

  describe ".extract" do
    it "returns the raw value at path when there is no transform" do
      expect(described_class.extract({ "status" => "active" }, { path: "status" })).to eq("active")
    end

    it "applies the named transform" do
      expect(described_class.extract({ "authoredOn" => "2026-07-19T10:00:00+09:00" }, { path: "authoredOn", transform: :datetime }))
        .to eq(Time.iso8601("2026-07-19T10:00:00+09:00"))
    end
  end

  describe ".partial_date" do
    it "parses a full date" do
      expect(described_class.partial_date("1985-03-20")).to eq(Date.new(1985, 3, 20))
    end

    it "parses a year-month, defaulting the day to 1" do
      expect(described_class.partial_date("1985-03")).to eq(Date.new(1985, 3, 1))
    end

    it "parses a year, defaulting month and day to 1" do
      expect(described_class.partial_date("1985")).to eq(Date.new(1985, 1, 1))
    end

    it "returns nil for a blank or unparseable value" do
      expect(described_class.partial_date("")).to be_nil
      expect(described_class.partial_date("not-a-date")).to be_nil
    end
  end

  describe ".datetime" do
    it "parses a tz-aware ISO8601 dateTime" do
      expect(described_class.datetime("2026-07-19T09:00:00+09:00")).to eq(Time.iso8601("2026-07-19T09:00:00+09:00"))
    end

    it "returns nil for blank or invalid" do
      expect(described_class.datetime(nil)).to be_nil
      expect(described_class.datetime("garbage")).to be_nil
    end
  end

  describe ".coding_code (single CodeableConcept)" do
    it "reads the first coding's code" do
      concept = { "coding" => [{ "code" => "620004422", "display" => "アムロジピン錠5mg" }], "text" => "x" }
      expect(described_class.coding_code(concept)).to eq("620004422")
    end

    it "is nil-safe for nil / no coding" do
      expect(described_class.coding_code(nil)).to be_nil
      expect(described_class.coding_code({ "text" => "x" })).to be_nil
    end
  end

  describe ".concept_list_code (array of CodeableConcepts)" do
    it "reads the first concept's first coding code" do
      concepts = [{ "coding" => [{ "code" => "doctor" }] }]
      expect(described_class.concept_list_code(concepts)).to eq("doctor")
    end

    it "is nil-safe for nil / empty" do
      expect(described_class.concept_list_code(nil)).to be_nil
      expect(described_class.concept_list_code([])).to be_nil
    end
  end

  describe ".concept_text" do
    it "joins concept text and the first coding display" do
      concept = { "coding" => [{ "display" => "血液検査" }], "text" => "検査オーダー" }
      expect(described_class.concept_text(concept)).to eq("検査オーダー 血液検査")
    end

    it "returns nil when both text and display are absent" do
      expect(described_class.concept_text({ "coding" => [{ "code" => "x" }] })).to be_nil
      expect(described_class.concept_text(nil)).to be_nil
    end
  end

  describe "HumanName transforms" do
    let(:names) do
      [
        { "use" => "official", "family" => "山田", "given" => %w[太郎 次郎] },
        { "family" => "ヤマダ", "given" => ["タロウ"] }
      ]
    end

    it "extracts the official family" do
      expect(described_class.official_family(names)).to eq("山田")
    end

    it "space-joins the official given names" do
      expect(described_class.official_given(names)).to eq("太郎 次郎")
    end

    it "falls back to the first name when none is official" do
      expect(described_class.official_family([{ "family" => "佐藤" }])).to eq("佐藤")
    end

    it "collects every representation (incl. kana) into name_text" do
      text = described_class.all_name_representations(names)
      expect(text).to include("山田", "太郎", "次郎", "ヤマダ", "タロウ")
    end

    it "is nil/empty-safe" do
      expect(described_class.official_family(nil)).to be_nil
      expect(described_class.official_given(nil)).to eq("")
      expect(described_class.all_name_representations(nil)).to eq("")
    end
  end

  describe ".address_text" do
    it "flattens text/line/city/state/postalCode in order" do
      address = { "text" => "東京都千代田区1-1-1", "line" => ["1-1-1"], "city" => "千代田区", "postalCode" => "100-0001" }
      result = described_class.address_text(address)
      expect(result).to include("東京都千代田区1-1-1", "1-1-1", "千代田区", "100-0001")
    end

    it "returns nil for a blank address" do
      expect(described_class.address_text(nil)).to be_nil
      expect(described_class.address_text({})).to be_nil
    end
  end
end
