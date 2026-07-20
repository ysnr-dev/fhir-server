require "rails_helper"

# Terminology is now the single source of truth for these ValueSets, so the exact
# code lists are locked here -- an accidental edit surfaces as a failing test
# rather than a silently changed validation.
RSpec.describe Fhir::Terminology do
  it "defines the administrative-gender ValueSet" do
    expect(described_class::GENDER).to eq(%w[male female other unknown])
  end

  it "defines the MedicationRequest status and intent ValueSets" do
    expect(described_class::MEDICATION_REQUEST_STATUS)
      .to eq(%w[active on-hold cancelled completed entered-in-error stopped draft unknown])
    expect(described_class::MEDICATION_REQUEST_INTENT)
      .to eq(%w[proposal plan order original-order reflex-order filler-order instance-order option])
  end

  it "defines the ServiceRequest status and intent ValueSets" do
    expect(described_class::SERVICE_REQUEST_STATUS)
      .to eq(%w[draft active on-hold revoked completed entered-in-error unknown])
    expect(described_class::SERVICE_REQUEST_INTENT)
      .to eq(%w[proposal plan directive order original-order reflex-order filler-order instance-order option])
  end

  it "defines the Encounter and Location ValueSets" do
    expect(described_class::ENCOUNTER_STATUS)
      .to eq(%w[planned arrived triaged in-progress onleave finished cancelled entered-in-error unknown])
    expect(described_class::LOCATION_STATUS).to eq(%w[active suspended inactive])
    expect(described_class::LOCATION_MODE).to eq(%w[instance kind])
  end

  it "defines the JP Core identifier systems and OIDs" do
    expect(described_class::MEDICAL_RECORD_NUMBER_OID).to eq("urn:oid:1.2.392.100495.20.3.51")
    expect(described_class::MEDICATION_RP_NUMBER_SYSTEM)
      .to eq("http://jpfhir.jp/fhir/core/mhlw/IdSystem/Medication-RPGroupNumber")
    expect(described_class::MEDICATION_ORDER_IN_RP_SYSTEM)
      .to eq("http://jpfhir.jp/fhir/core/mhlw/IdSystem/MedicationAdministrationIndex")
  end

  it "freezes the ValueSet arrays" do
    expect(described_class::GENDER).to be_frozen
    expect(described_class::MEDICATION_REQUEST_STATUS).to be_frozen
  end
end
