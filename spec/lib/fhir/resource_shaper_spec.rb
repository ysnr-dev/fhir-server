require "rails_helper"

RSpec.describe Fhir::ResourceShaper do
  def params(query)
    Fhir::SearchParams.parse(query)
  end

  let(:resource) do
    {
      "resourceType" => "Patient",
      "id" => "p1",
      "meta" => { "versionId" => "1", "lastUpdated" => "2026-07-21T00:00:00.000Z" },
      "text" => { "status" => "generated", "div" => "<div>...</div>" },
      "name" => [{ "family" => "山田" }],
      "gender" => "male"
    }
  end

  describe ".build" do
    it "returns nil when no shaping applies" do
      expect(described_class.build(params("status=active"))).to be_nil
      expect(described_class.build(params("_summary=false"))).to be_nil
      # _summary=true needs the spec's per-resource summary element tables -- unsupported.
      expect(described_class.build(params("_summary=true"))).to be_nil
      # count is handled upstream (no entries at all).
      expect(described_class.build(params("_summary=count"))).to be_nil
    end

    it "lets _summary win over _elements" do
      shaper = described_class.build(params("_summary=text&_elements=name"))

      shaped = shaper.call(resource)
      expect(shaped.keys).to contain_exactly("resourceType", "id", "meta", "text")
    end
  end

  describe "_summary=text" do
    it "keeps only resourceType/id/meta/text and tags SUBSETTED" do
      shaped = described_class.build(params("_summary=text")).call(resource)

      expect(shaped.keys).to contain_exactly("resourceType", "id", "meta", "text")
      expect(shaped["meta"]["tag"]).to include(described_class::SUBSETTED_TAG)
    end
  end

  describe "_summary=data" do
    it "drops only text and tags SUBSETTED" do
      shaped = described_class.build(params("_summary=data")).call(resource)

      expect(shaped.keys).to contain_exactly("resourceType", "id", "meta", "name", "gender")
      expect(shaped["meta"]["tag"]).to include(described_class::SUBSETTED_TAG)
    end
  end

  describe "_elements" do
    it "keeps the mandatory keys plus the requested elements" do
      shaped = described_class.build(params("_elements=name")).call(resource)

      expect(shaped.keys).to contain_exactly("resourceType", "id", "meta", "name")
    end

    it "ignores unknown element names" do
      shaped = described_class.build(params("_elements=name,bogus")).call(resource)

      expect(shaped.keys).to contain_exactly("resourceType", "id", "meta", "name")
    end
  end

  it "does not duplicate an existing SUBSETTED tag and does not mutate the input" do
    tagged = resource.merge("meta" => resource["meta"].merge("tag" => [described_class::SUBSETTED_TAG.dup]))

    shaped = described_class.build(params("_summary=data")).call(tagged)

    expect(shaped["meta"]["tag"].length).to eq(1)
    expect(resource).not_to have_key("tag")
    expect(resource["meta"]).not_to have_key("tag")
  end
end
