require "rails_helper"

RSpec.describe Fhir::Scopes do
  describe ".valid?" do
    it "accepts system scopes with type and access wildcards" do
      expect(described_class.valid?("system/Patient.read")).to be(true)
      expect(described_class.valid?("system/*.write")).to be(true)
      expect(described_class.valid?("system/Encounter.*")).to be(true)
      expect(described_class.valid?("system/*.*")).to be(true)
    end

    it "rejects launch-context and malformed scopes" do
      expect(described_class.valid?("patient/Patient.read")).to be(false)
      expect(described_class.valid?("user/*.read")).to be(false)
      expect(described_class.valid?("system/patient.read")).to be(false)
      expect(described_class.valid?("system/Patient.delete")).to be(false)
      expect(described_class.valid?("openid")).to be(false)
    end
  end

  describe "#allows?" do
    it "matches exact type and access" do
      scopes = described_class.new(%w[system/Patient.read])

      expect(scopes.allows?("Patient", :read)).to be(true)
      expect(scopes.allows?("Patient", :write)).to be(false)
      expect(scopes.allows?("Observation", :read)).to be(false)
    end

    it "honors type and access wildcards" do
      expect(described_class.new(%w[system/*.read]).allows?("Observation", :read)).to be(true)
      expect(described_class.new(%w[system/Patient.*]).allows?("Patient", :write)).to be(true)
      expect(described_class.new(%w[system/*.*]).allows?("Coverage", :write)).to be(true)
    end

    it "requires a wildcard-type grant for the '*' pseudo-type (system-wide endpoints)" do
      expect(described_class.new(%w[system/Patient.read]).allows?("*", :read)).to be(false)
      expect(described_class.new(%w[system/*.read]).allows?("*", :read)).to be(true)
    end

    it "ignores unparseable scopes" do
      expect(described_class.new(%w[patient/Patient.read bogus]).allows?("Patient", :read)).to be(false)
    end
  end
end
