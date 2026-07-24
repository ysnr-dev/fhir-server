require "rails_helper"

RSpec.describe Fhir::Scopes do
  describe ".valid?" do
    it "accepts system scopes with type and access wildcards" do
      expect(described_class.valid?("system/Patient.read")).to be(true)
      expect(described_class.valid?("system/*.write")).to be(true)
      expect(described_class.valid?("system/Encounter.*")).to be(true)
      expect(described_class.valid?("system/*.*")).to be(true)
    end

    it "accepts read-only patient scopes" do
      expect(described_class.valid?("patient/Patient.read")).to be(true)
      expect(described_class.valid?("patient/*.read")).to be(true)
    end

    it "rejects patient scopes that would grant writes" do
      expect(described_class.valid?("patient/Observation.write")).to be(false)
      expect(described_class.valid?("patient/Observation.*")).to be(false)
    end

    it "rejects unimplemented launch contexts and malformed scopes" do
      expect(described_class.valid?("user/*.read")).to be(false)
      expect(described_class.valid?("system/patient.read")).to be(false)
      expect(described_class.valid?("system/Patient.delete")).to be(false)
      expect(described_class.valid?("openid")).to be(false)
    end
  end

  describe ".valid_system? / .valid_patient?" do
    it "separates the two families" do
      expect(described_class.valid_system?("system/Patient.read")).to be(true)
      expect(described_class.valid_system?("patient/Patient.read")).to be(false)
      expect(described_class.valid_patient?("patient/Patient.read")).to be(true)
      expect(described_class.valid_patient?("system/Patient.read")).to be(false)
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
      expect(described_class.new(%w[user/Patient.read bogus]).allows?("Patient", :read)).to be(false)
    end

    it "grants patient scopes read but never write" do
      scopes = described_class.new(%w[patient/Observation.read])

      expect(scopes.allows?("Observation", :read)).to be(true)
      expect(scopes.allows?("Observation", :write)).to be(false)
      expect(scopes.allows?("Condition", :read)).to be(false)
    end
  end

  describe "#system_allows?" do
    # patient/*.read structurally satisfies allows?("*", :read), which is how
    # server-wide endpoints ask "may this token see everything?". Those
    # endpoints must use system_allows? or a launch token would pass.
    it "ignores patient grants where allows? would accept them" do
      scopes = described_class.new(%w[patient/*.read])

      expect(scopes.allows?("*", :read)).to be(true)
      expect(scopes.system_allows?("*", :read)).to be(false)
      expect(scopes.system_allows?("Observation", :read)).to be(false)
    end

    it "behaves like allows? for system grants" do
      scopes = described_class.new(%w[system/*.read])

      expect(scopes.system_allows?("*", :read)).to be(true)
      expect(scopes.system_allows?("Observation", :read)).to be(true)
      expect(scopes.system_allows?("Observation", :write)).to be(false)
    end
  end

  describe "#patient_grants?" do
    it "reports whether any patient-family grant is present" do
      expect(described_class.new(%w[patient/Patient.read]).patient_grants?).to be(true)
      expect(described_class.new(%w[system/*.*]).patient_grants?).to be(false)
    end
  end
end
