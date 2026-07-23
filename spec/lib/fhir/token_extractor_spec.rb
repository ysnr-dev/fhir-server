require "rails_helper"

RSpec.describe Fhir::TokenExtractor do
  def rows(content, spec)
    described_class.rows(content, spec)
  end

  it "extracts a primitive code with no system (:code)" do
    result = rows({ "status" => "final" }, { "status" => { path: "status", kind: :code } })

    expect(result).to eq([{ param_name: "status", system: nil, code: "final" }])
  end

  it "extracts each entry of a primitive code array (:code_list)" do
    result = rows({ "category" => %w[food medication] },
                  { "category" => { path: "category", kind: :code_list } })

    expect(result).to eq([
                           { param_name: "category", system: nil, code: "food" },
                           { param_name: "category", system: nil, code: "medication" }
                         ])
  end

  it "extracts every coding of a single CodeableConcept (:codeable_concept)" do
    content = { "code" => { "coding" => [
      { "system" => "http://loinc.org", "code" => "1234-5" },
      { "system" => "urn:oid:1.2.392", "code" => "3B035" }
    ] } }

    result = rows(content, { "code" => { path: "code", kind: :codeable_concept } })

    expect(result).to contain_exactly(
      { param_name: "code", system: "http://loinc.org", code: "1234-5" },
      { param_name: "code", system: "urn:oid:1.2.392", code: "3B035" }
    )
  end

  it "flattens codings across a list of CodeableConcepts (:codeable_concept_list)" do
    content = { "category" => [
      { "coding" => [{ "system" => "s1", "code" => "a" }] },
      { "coding" => [{ "system" => "s2", "code" => "b" }, { "code" => "c" }] }
    ] }

    result = rows(content, { "category" => { path: "category", kind: :codeable_concept_list } })

    expect(result).to contain_exactly(
      { param_name: "category", system: "s1", code: "a" },
      { param_name: "category", system: "s2", code: "b" },
      { param_name: "category", system: nil, code: "c" }
    )
  end

  it "extracts a bare Coding (:coding)" do
    content = { "class" => { "system" => "http://act", "code" => "AMB" } }

    result = rows(content, { "class" => { path: "class", kind: :coding } })

    expect(result).to eq([{ param_name: "class", system: "http://act", code: "AMB" }])
  end

  it "extracts each of a bare Coding array (:coding_list)" do
    content = { "modality" => [
      { "system" => "http://dicom", "code" => "CT" },
      { "system" => "http://dicom", "code" => "MR" }
    ] }

    result = rows(content, { "modality" => { path: "modality", kind: :coding_list } })

    expect(result).to contain_exactly(
      { param_name: "modality", system: "http://dicom", code: "CT" },
      { param_name: "modality", system: "http://dicom", code: "MR" }
    )
  end

  it "extracts an Identifier's system and value (:identifier)" do
    content = { "accessionIdentifier" => { "system" => "http://acc", "value" => "A-1" } }

    result = rows(content, { "accession" => { path: "accessionIdentifier", kind: :identifier } })

    expect(result).to eq([{ param_name: "accession", system: "http://acc", code: "A-1" }])
  end

  it "drops rows with a blank code and normalizes a blank system to nil" do
    content = { "code" => { "coding" => [
      { "system" => "", "code" => "x" },
      { "system" => "s", "code" => "" },
      { "system" => "s" }
    ] } }

    result = rows(content, { "code" => { path: "code", kind: :codeable_concept } })

    expect(result).to eq([{ param_name: "code", system: nil, code: "x" }])
  end

  it "returns nothing when the path is absent or the node is the wrong shape" do
    spec = { "code" => { path: "code", kind: :codeable_concept } }

    expect(rows({}, spec)).to eq([])
    expect(rows({ "code" => "not-a-concept" }, spec)).to eq([])
  end
end
