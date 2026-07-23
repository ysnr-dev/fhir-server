require "rails_helper"

RSpec.describe Fhir::Profile::ElementTree do
  # Trimmed StructureDefinition shape, matching what lib/tasks/jp_core.rake
  # writes to vendor/jp_core/ (see strip_element there).
  def structure_definition(type, elements)
    { "url" => "http://jpfhir.jp/fhir/core/StructureDefinition/JP_#{type}", "type" => type,
      "snapshot" => { "element" => elements } }
  end

  def element(id, **rest)
    path = id.split(".").map { |segment| segment.split(":").first }.join(".")
    { "id" => id, "path" => path }.merge(rest.transform_keys(&:to_s))
  end

  describe ".build" do
    it "builds a parent-child tree keyed by element name" do
      definition = structure_definition("Foo", [
        element("Foo", min: 0, max: "*"),
        element("Foo.status", min: 1, max: "1", type: [{ "code" => "code" }]),
        element("Foo.subject", min: 0, max: "1", type: [{ "code" => "Reference" }])
      ])

      root = described_class.build(definition)

      expect(root.path).to eq("Foo")
      expect(root.children.keys).to contain_exactly("status", "subject")
      expect(root.children["status"].min).to eq(1)
      expect(root.children["status"].max).to eq("1")
    end

    it "returns nil for a StructureDefinition with no snapshot elements" do
      expect(described_class.build(structure_definition("Foo", []))).to be_nil
    end

    it "attaches slice elements to the slicing-definition sibling's `slices`, not as a plain child" do
      definition = structure_definition("Foo", [
        element("Foo", min: 0, max: "*"),
        element("Foo.identifier", min: 2, max: "*",
                slicing: { "discriminator" => [{ "type" => "value", "path" => "system" }], "rules" => "open" }),
        element("Foo.identifier:rp", sliceName: "rp", min: 1, max: "1"),
        element("Foo.identifier:rp.system", min: 1, max: "1", type: [{ "code" => "uri" }],
                fixedUri: "http://example.com/rp"),
        element("Foo.identifier:rp.value", min: 1, max: "1", type: [{ "code" => "string" }])
      ])

      root = described_class.build(definition)
      base = root.children["identifier"]

      expect(root.children.keys).to eq(["identifier"]) # no separate "identifier:rp" key
      expect(base.slices.map(&:slice_name)).to eq(["rp"])

      slice = base.slices.first
      expect(slice.children.keys).to contain_exactly("system", "value")
      expect(slice.discriminator).to eq([{ path: "system", value: "http://example.com/rp" }])
    end

    it "resolves an extension slice's discriminator from the extension's own profile canonical, " \
       "not a local fixed value" do
      definition = structure_definition("Foo", [
        element("Foo", min: 0, max: "*"),
        element("Foo.extension", min: 0, max: "*",
                slicing: { "discriminator" => [{ "type" => "value", "path" => "url" }], "rules" => "open" }),
        element("Foo.extension:race", sliceName: "race", min: 0, max: "1",
                type: [{ "code" => "Extension", "profile" => ["http://jpfhir.jp/fhir/core/Extension/StructureDefinition/JP_Patient_Race|1.2.0"] }])
      ])

      root = described_class.build(definition)
      slice = root.children["extension"].slices.first

      expect(slice.discriminator).to eq(
        [{ path: "url", value: "http://jpfhir.jp/fhir/core/Extension/StructureDefinition/JP_Patient_Race" }]
      )
    end

    it "leaves a slice's discriminator nil when it can't be resolved (unsupported discriminator type)" do
      definition = structure_definition("Foo", [
        element("Foo", min: 0, max: "*"),
        element("Foo.identifier", min: 0, max: "*",
                slicing: { "discriminator" => [{ "type" => "profile", "path" => "$this" }], "rules" => "open" }),
        element("Foo.identifier:weird", sliceName: "weird", min: 0, max: "1")
      ])

      root = described_class.build(definition)
      slice = root.children["identifier"].slices.first

      expect(slice.discriminator).to be_nil
    end

    it "leaves a slice's discriminator nil when the declared discriminator path can't be found locally " \
       "and isn't the extension-url special case" do
      definition = structure_definition("Foo", [
        element("Foo", min: 0, max: "*"),
        element("Foo.identifier", min: 0, max: "*",
                slicing: { "discriminator" => [{ "type" => "value", "path" => "type.coding.code" }], "rules" => "open" }),
        element("Foo.identifier:weird", sliceName: "weird", min: 0, max: "1")
      ])

      root = described_class.build(definition)
      slice = root.children["identifier"].slices.first

      expect(slice.discriminator).to be_nil
    end
  end
end
