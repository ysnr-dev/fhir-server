require "rails_helper"

RSpec.describe Fhir::Profile::DefinitionStore do
  describe ".structure_definition" do
    it "loads a vendored StructureDefinition by its canonical URL" do
      definition = described_class.structure_definition("http://jpfhir.jp/fhir/core/StructureDefinition/JP_Patient")

      expect(definition["url"]).to eq("http://jpfhir.jp/fhir/core/StructureDefinition/JP_Patient")
      expect(definition["type"]).to eq("Patient")
      expect(definition.dig("snapshot", "element")).not_to be_empty
    end

    it "ignores a |version suffix on the canonical URL" do
      definition = described_class.structure_definition(
        "http://jpfhir.jp/fhir/core/StructureDefinition/JP_Patient|1.2.0"
      )

      expect(definition["url"]).to eq("http://jpfhir.jp/fhir/core/StructureDefinition/JP_Patient")
    end

    it "returns nil for a URL that isn't vendored" do
      expect(described_class.structure_definition("http://example.com/not-vendored")).to be_nil
    end
  end

  describe ".known_profile?" do
    # Every registry profile that names an Implementation Guide (i.e. isn't a
    # bare HL7 base profile) must actually be vendored -- otherwise the entry
    # silently loses profile validation. Written against the base-HL7 namespace
    # rather than .known_profile? itself so the assertion can't go tautological.
    it "is true for every IG profile the resource registry declares" do
      Fhir::ResourceRegistry::ENTRIES.each_value do |entry|
        next if entry[:profile].start_with?("http://hl7.org/fhir/StructureDefinition/")

        expect(described_class.known_profile?(entry[:profile])).to be(true), "expected #{entry[:profile]} to be vendored"
      end
    end

    it "is false for an unvendored URL" do
      expect(described_class.known_profile?("http://example.com/not-vendored")).to be(false)
    end
  end

  describe ".value_set and .code_system" do
    it "returns nil when the package didn't include the referenced ValueSet/CodeSystem" do
      # Most JP Core required bindings name ValueSets that live in the separate
      # terminology package rather than this one, so the store has to tolerate a
      # dangling binding -- see lib/tasks/jp_core.rake.
      expect(described_class.value_set("http://jpfhir.jp/fhir/core/ValueSet/does-not-exist")).to be_nil
      expect(described_class.code_system("http://jpfhir.jp/fhir/core/CodeSystem/does-not-exist")).to be_nil
    end
  end

  describe ".expansion" do
    it "returns nil for a ValueSet that isn't vendored" do
      expect(described_class.expansion("http://hl7.org/fhir/ValueSet/administrative-gender")).to be_nil
    end

    # JP_DICOMModality_VS (bound by ImagingStudy.modality) is the one JP Core
    # ValueSet the package does ship, and the only JP Core required binding this
    # engine can actually check. It expands without its CodeSystem because the
    # single compose.include carries inline concepts.
    it "expands the vendored JP Core DICOM modality ValueSet" do
      expansion = described_class.expansion("http://jpfhir.jp/fhir/core/ValueSet/JP_DICOMModality_VS")

      expect(expansion).to include("CT")
    end
  end
end
