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

    it "accepts the refresh-token and identity context scopes" do
      expect(described_class.valid?("offline_access")).to be(true)
      expect(described_class.valid?("online_access")).to be(true)
      expect(described_class.valid?("openid")).to be(true)
      expect(described_class.valid?("fhirUser")).to be(true)
      expect(described_class.valid?("profile")).to be(true)
    end

    it "rejects unimplemented launch contexts and malformed scopes" do
      expect(described_class.valid?("user/*.read")).to be(false)
      expect(described_class.valid?("system/patient.read")).to be(false)
      expect(described_class.valid?("system/Patient.delete")).to be(false)
      expect(described_class.valid?("email")).to be(false)
    end

    it "accepts SMART v2 CRUDS access on system scopes" do
      expect(described_class.valid?("system/Patient.rs")).to be(true)
      expect(described_class.valid?("system/*.cud")).to be(true)
      expect(described_class.valid?("system/Encounter.cruds")).to be(true)
      expect(described_class.valid?("system/Observation.r")).to be(true)
    end

    it "accepts read-only SMART v2 CRUDS access on patient scopes" do
      expect(described_class.valid?("patient/Observation.rs")).to be(true)
      expect(described_class.valid?("patient/*.rs")).to be(true)
      expect(described_class.valid?("patient/Observation.r")).to be(true)
      expect(described_class.valid?("patient/Observation.s")).to be(true)
    end

    it "rejects patient v2 scopes that would grant writes" do
      expect(described_class.valid?("patient/Observation.cruds")).to be(false)
      expect(described_class.valid?("patient/Observation.cud")).to be(false)
      expect(described_class.valid?("patient/Observation.rus")).to be(false)
    end

    it "rejects malformed v2 access: non-canonical order, repeats, or empty" do
      expect(described_class.valid?("system/Patient.sr")).to be(false)
      expect(described_class.valid?("system/Patient.rr")).to be(false)
      expect(described_class.valid?("system/Patient.x")).to be(false)
      expect(described_class.valid?("system/Patient.")).to be(false)
    end

    it "rejects v2 ?query search-parameter constraints as unsupported" do
      expect(described_class.valid?("patient/Observation.rs?category=laboratory")).to be(false)
    end
  end

  describe ".valid_context? / .refresh_requested? / .identity_requested?" do
    it "recognises the refresh and identity context scopes" do
      expect(described_class.valid_context?("offline_access")).to be(true)
      expect(described_class.valid_context?("online_access")).to be(true)
      expect(described_class.valid_context?("openid")).to be(true)
      expect(described_class.valid_context?("fhirUser")).to be(true)
      expect(described_class.valid_context?("patient/*.read")).to be(false)
    end

    it "detects a refresh request from the refresh scopes only" do
      expect(described_class.refresh_requested?(%w[patient/*.read offline_access])).to be(true)
      expect(described_class.refresh_requested?(%w[patient/*.read online_access])).to be(true)
      expect(described_class.refresh_requested?(%w[patient/*.read openid])).to be(false)
      expect(described_class.refresh_requested?(%w[patient/*.read])).to be(false)
    end

    it "detects an identity request from openid only" do
      expect(described_class.identity_requested?(%w[patient/*.read openid])).to be(true)
      # fhirUser/profile shape the id_token but do not trigger one on their own.
      expect(described_class.identity_requested?(%w[patient/*.read fhirUser])).to be(false)
      expect(described_class.identity_requested?(%w[patient/*.read offline_access])).to be(false)
    end
  end

  describe "#allows? with context scopes" do
    it "grants no resource access through refresh or identity scopes" do
      scopes = described_class.new(%w[offline_access online_access openid fhirUser profile])
      expect(scopes.allows?("Patient", :read)).to be(false)
      expect(scopes.allows?("*", :read)).to be(false)
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

    it "maps SMART v2 CRUDS letters onto read/write" do
      rs = described_class.new(%w[system/Observation.rs])
      expect(rs.allows?("Observation", :read)).to be(true)
      expect(rs.allows?("Observation", :write)).to be(false)

      cud = described_class.new(%w[system/Observation.cud])
      expect(cud.allows?("Observation", :read)).to be(false)
      expect(cud.allows?("Observation", :write)).to be(true)

      cruds = described_class.new(%w[system/*.cruds])
      expect(cruds.allows?("Observation", :read)).to be(true)
      expect(cruds.allows?("Coverage", :write)).to be(true)
    end

    it "treats a v2 search-only letter as read" do
      scopes = described_class.new(%w[system/Observation.s])
      expect(scopes.allows?("Observation", :read)).to be(true)
      expect(scopes.allows?("Observation", :write)).to be(false)
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
