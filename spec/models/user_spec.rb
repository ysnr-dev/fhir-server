require "rails_helper"

RSpec.describe User do
  def create_patient
    Patient.create!(id: SecureRandom.uuid, content: { "resourceType" => "Patient" },
                    version_id: 1, last_updated: Time.current)
  end

  let(:patient) { create_patient }

  describe ".authenticate" do
    before { described_class.create!(email: "p@example.com", patient_id: patient.id, password: "correct-horse-battery") }

    it "accepts the right password" do
      expect(described_class.authenticate(email: "p@example.com", password: "correct-horse-battery")).to be_present
    end

    it "normalises the email before looking up" do
      expect(described_class.authenticate(email: "  P@Example.COM ", password: "correct-horse-battery")).to be_present
    end

    it "rejects a wrong password, an unknown account, and blank input alike" do
      expect(described_class.authenticate(email: "p@example.com", password: "wrong")).to be_nil
      expect(described_class.authenticate(email: "nobody@example.com", password: "correct-horse-battery")).to be_nil
      expect(described_class.authenticate(email: "", password: "")).to be_nil
      expect(described_class.authenticate(email: nil, password: nil)).to be_nil
    end
  end

  describe "the 1:1 binding to a patient" do
    it "rejects a second account for the same patient" do
      described_class.create!(email: "a@example.com", patient_id: patient.id, password: "correct-horse-battery")

      second = described_class.new(email: "b@example.com", patient_id: patient.id, password: "correct-horse-battery")
      expect(second).not_to be_valid
    end

    it "rejects a duplicate email" do
      described_class.create!(email: "a@example.com", patient_id: patient.id, password: "correct-horse-battery")

      duplicate = described_class.new(email: "a@example.com", patient_id: create_patient.id, password: "correct-horse-battery")
      expect(duplicate).not_to be_valid
    end
  end
end
