require "rails_helper"

RSpec.describe Fhir::JsonPatch do
  def apply(document, operations)
    described_class.apply(document, operations)
  end

  describe "add" do
    it "adds a new object member" do
      expect(apply({ "a" => 1 }, [{ "op" => "add", "path" => "/b", "value" => 2 }])).to eq("a" => 1, "b" => 2)
    end

    it "replaces an existing object member (add semantics)" do
      expect(apply({ "a" => 1 }, [{ "op" => "add", "path" => "/a", "value" => 9 }])).to eq("a" => 9)
    end

    it "inserts into an array, shifting later elements" do
      expect(apply({ "a" => [1, 3] }, [{ "op" => "add", "path" => "/a/1", "value" => 2 }])).to eq("a" => [1, 2, 3])
    end

    it "appends with the '-' index" do
      expect(apply({ "a" => [1] }, [{ "op" => "add", "path" => "/a/-", "value" => 2 }])).to eq("a" => [1, 2])
    end

    it "allows adding at index == length" do
      expect(apply({ "a" => [1] }, [{ "op" => "add", "path" => "/a/1", "value" => 2 }])).to eq("a" => [1, 2])
    end

    it "fails on an array index beyond length" do
      expect { apply({ "a" => [1] }, [{ "op" => "add", "path" => "/a/2", "value" => 2 }]) }
        .to raise_error(described_class::ApplyFailure)
    end

    it "accepts an explicit null value" do
      expect(apply({}, [{ "op" => "add", "path" => "/a", "value" => nil }])).to eq("a" => nil)
    end

    it "replaces the whole document at the root pointer" do
      expect(apply({ "a" => 1 }, [{ "op" => "add", "path" => "", "value" => { "b" => 2 } }])).to eq("b" => 2)
    end

    it "fails when an intermediate path segment is missing" do
      expect { apply({}, [{ "op" => "add", "path" => "/x/y", "value" => 1 }]) }
        .to raise_error(described_class::ApplyFailure)
    end
  end

  describe "remove" do
    it "removes an object member" do
      expect(apply({ "a" => 1, "b" => 2 }, [{ "op" => "remove", "path" => "/b" }])).to eq("a" => 1)
    end

    it "removes an array element, shifting later elements" do
      expect(apply({ "a" => [1, 2, 3] }, [{ "op" => "remove", "path" => "/a/1" }])).to eq("a" => [1, 3])
    end

    it "fails on a nonexistent member" do
      expect { apply({ "a" => 1 }, [{ "op" => "remove", "path" => "/b" }]) }
        .to raise_error(described_class::ApplyFailure)
    end
  end

  describe "replace" do
    it "replaces an object member" do
      expect(apply({ "a" => 1 }, [{ "op" => "replace", "path" => "/a", "value" => 2 }])).to eq("a" => 2)
    end

    it "replaces an array element in place" do
      expect(apply({ "a" => [1, 2, 3] }, [{ "op" => "replace", "path" => "/a/1", "value" => 9 }])).to eq("a" => [1, 9, 3])
    end

    it "fails on a nonexistent member" do
      expect { apply({}, [{ "op" => "replace", "path" => "/a", "value" => 1 }]) }
        .to raise_error(described_class::ApplyFailure)
    end
  end

  describe "move" do
    it "moves a value between locations" do
      expect(apply({ "a" => 1 }, [{ "op" => "move", "from" => "/a", "path" => "/b" }])).to eq("b" => 1)
    end

    it "fails when moving into its own child" do
      expect { apply({ "a" => { "b" => 1 } }, [{ "op" => "move", "from" => "/a", "path" => "/a/c" }]) }
        .to raise_error(described_class::ApplyFailure)
    end
  end

  describe "copy" do
    it "copies a value" do
      expect(apply({ "a" => [1] }, [{ "op" => "copy", "from" => "/a", "path" => "/b" }])).to eq("a" => [1], "b" => [1])
    end

    it "deep-copies so the copy is independent" do
      result = apply({ "a" => { "x" => 1 } }, [
        { "op" => "copy", "from" => "/a", "path" => "/b" },
        { "op" => "replace", "path" => "/b/x", "value" => 2 }
      ])
      expect(result).to eq("a" => { "x" => 1 }, "b" => { "x" => 2 })
    end
  end

  describe "test" do
    it "passes on deep equality" do
      expect(apply({ "a" => { "b" => [1, nil] } }, [{ "op" => "test", "path" => "/a", "value" => { "b" => [1, nil] } }]))
        .to eq("a" => { "b" => [1, nil] })
    end

    it "fails on inequality with ApplyFailure" do
      expect { apply({ "a" => 1 }, [{ "op" => "test", "path" => "/a", "value" => 2 }]) }
        .to raise_error(described_class::ApplyFailure)
    end
  end

  describe "pointer syntax" do
    it "unescapes ~1 then ~0 (so ~01 means literal ~1)" do
      document = { "a/b" => 1, "~1" => 2, "m~n" => 3 }
      expect(apply(document, [{ "op" => "test", "path" => "/a~1b", "value" => 1 }])).to eq(document)
      expect(apply(document, [{ "op" => "test", "path" => "/~01", "value" => 2 }])).to eq(document)
      expect(apply(document, [{ "op" => "test", "path" => "/m~0n", "value" => 3 }])).to eq(document)
    end

    it "rejects a pointer not starting with '/' as InvalidPatch" do
      expect { apply({}, [{ "op" => "add", "path" => "a", "value" => 1 }]) }
        .to raise_error(described_class::InvalidPatch)
    end

    it "rejects array indexes with leading zeros" do
      expect { apply({ "a" => [1, 2] }, [{ "op" => "remove", "path" => "/a/01" }]) }
        .to raise_error(described_class::ApplyFailure)
    end
  end

  describe "patch document validation" do
    it "rejects a non-array document" do
      expect { apply({}, { "op" => "add", "path" => "/a", "value" => 1 }) }
        .to raise_error(described_class::InvalidPatch)
    end

    it "rejects an unknown op" do
      expect { apply({}, [{ "op" => "merge", "path" => "/a", "value" => 1 }]) }
        .to raise_error(described_class::InvalidPatch)
    end

    it "rejects a missing path" do
      expect { apply({}, [{ "op" => "add", "value" => 1 }]) }.to raise_error(described_class::InvalidPatch)
    end

    it "rejects a missing value for add/replace/test" do
      expect { apply({}, [{ "op" => "add", "path" => "/a" }]) }.to raise_error(described_class::InvalidPatch)
    end

    it "rejects a missing from for move/copy" do
      expect { apply({}, [{ "op" => "move", "path" => "/a" }]) }.to raise_error(described_class::InvalidPatch)
    end
  end

  it "does not mutate the input document" do
    document = { "a" => { "b" => 1 } }
    apply(document, [{ "op" => "replace", "path" => "/a/b", "value" => 2 }])
    expect(document).to eq("a" => { "b" => 1 })
  end

  it "applies operations sequentially" do
    result = apply({ "name" => [{ "family" => "山田" }] }, [
      { "op" => "test", "path" => "/name/0/family", "value" => "山田" },
      { "op" => "replace", "path" => "/name/0/family", "value" => "佐藤" },
      { "op" => "add", "path" => "/name/0/given", "value" => ["花子"] }
    ])
    expect(result).to eq("name" => [{ "family" => "佐藤", "given" => ["花子"] }])
  end
end
