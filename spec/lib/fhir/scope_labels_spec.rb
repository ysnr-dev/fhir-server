require "rails_helper"

RSpec.describe Fhir::ScopeLabels do
  # ラベル漏れは「同意画面に生の型名が出る」「管理画面の選択肢が英語のまま」という
  # 形で静かに現れる。25型目が増えたときにここで落ちるようにしておく。
  it "labels every supported resource type" do
    missing = Fhir::ResourceRegistry.types.reject { |type| described_class::RESOURCE.key?(type) }

    expect(missing).to be_empty, "ラベル未定義のリソース型: #{missing.join(', ')}"
  end

  it "labels the wildcard type" do
    expect(described_class::RESOURCE).to have_key("*")
  end

  it "labels every context scope" do
    missing = Fhir::Scopes::CONTEXT_SCOPES.reject { |scope| described_class::CONTEXT.key?(scope) }

    expect(missing).to be_empty, "ラベル未定義のコンテキストスコープ: #{missing.join(', ')}"
  end

  it "labels every v1 access keyword" do
    expect(described_class::ACCESS.keys).to contain_exactly("read", "write", "*")
  end

  describe ".resource" do
    it "falls back to the bare type name" do
      expect(described_class.resource("Patient")).to eq("患者基本情報")
      expect(described_class.resource("NotAResource")).to eq("NotAResource")
    end
  end

  describe ".context" do
    it "returns nil for a non-context scope" do
      expect(described_class.context("offline_access")).to include("再ログインなし")
      expect(described_class.context("patient/*.read")).to be_nil
    end
  end
end
