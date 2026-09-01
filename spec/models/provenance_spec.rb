require "rails_helper"

RSpec.describe Provenance do
  def build_provenance(content)
    described_class.new(
      id: SecureRandom.uuid,
      version_id: 1,
      content: content,
      last_updated: Time.current
    )
  end

  describe "#sync_search_fields!" do
    it "extracts recorded" do
      provenance = build_provenance("recorded" => "2026-09-01T10:30:15+09:00")

      provenance.sync_search_fields!

      expect(provenance.recorded).to eq(Time.iso8601("2026-09-01T10:30:15+09:00"))
    end

    it "leaves recorded nil when absent" do
      provenance = build_provenance({})

      provenance.sync_search_fields!

      expect(provenance.recorded).to be_nil
    end
  end

  describe "#sync_tokens!" do
    # agent[].type は agent 配列を 1 段踏み越えた先の 0..1 CodeableConcept。
    # 代行入力では author と enterer の 2 件が並ぶので、両方が引けなければならない。
    it "indexes agent.type for every agent" do
      provenance = build_provenance(
        "agent" => [
          { "type" => { "coding" => [
            { "system" => "http://terminology.hl7.org/CodeSystem/provenance-participant-type",
              "code" => "author" }
          ] }, "who" => { "reference" => "Practitioner/p1" } },
          { "type" => { "coding" => [
            { "system" => "http://terminology.hl7.org/CodeSystem/provenance-participant-type",
              "code" => "enterer" }
          ] }, "who" => { "reference" => "Practitioner/p2" } }
        ]
      )
      provenance.save!

      provenance.sync_tokens!

      rows = provenance.resource_tokens.where(param_name: "agent-type").map { |t| [t.system, t.code] }
      expect(rows).to contain_exactly(
        ["http://terminology.hl7.org/CodeSystem/provenance-participant-type", "author"],
        ["http://terminology.hl7.org/CodeSystem/provenance-participant-type", "enterer"]
      )
    end

    # signature[].type は「配列の中の Coding 配列」。dig_path は配列を 1 段しか
    # 踏み越えないので :coding_list_nested がもう 1 段ほどく。これが無いと
    # signature-type は静かに 0 行になる。
    it "indexes signature.type through the nested coding array" do
      provenance = build_provenance(
        "signature" => [
          { "type" => [
              { "system" => "urn:iso-astm:E1762-95:2013", "code" => "1.2.840.10065.1.12.1.5" },
              { "system" => "urn:iso-astm:E1762-95:2013", "code" => "1.2.840.10065.1.12.1.1" }
            ],
            "when" => "2026-09-01T11:00:00+09:00",
            "who" => { "reference" => "Practitioner/p1" } }
        ]
      )
      provenance.save!

      provenance.sync_tokens!

      rows = provenance.resource_tokens.where(param_name: "signature-type").map(&:code)
      expect(rows).to contain_exactly("1.2.840.10065.1.12.1.5", "1.2.840.10065.1.12.1.1")
    end

    it "emits no rows when neither element is present" do
      provenance = build_provenance("recorded" => "2026-09-01T10:30:15+09:00")
      provenance.save!

      provenance.sync_tokens!

      expect(provenance.resource_tokens).to be_empty
    end
  end
end
