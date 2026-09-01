module ProvenancePayloadHelper
  # 代行入力の Provenance: 指示した医師(author)と、実際に入力した本人(enterer)を並べ、
  # enterer.onBehalfOf で「誰の指示で入れたか」を指す。target はオーダー本体。
  def valid_provenance_payload(target_reference:, author_id:, enterer_id: nil, **overrides)
    enterer_id ||= author_id
    {
      "resourceType" => "Provenance",
      "target" => [{ "reference" => target_reference }],
      "recorded" => "2026-09-01T10:30:15+09:00",
      "agent" => [
        {
          "type" => { "coding" => [
            { "system" => "http://terminology.hl7.org/CodeSystem/provenance-participant-type",
              "code" => "author" }
          ] },
          "who" => { "reference" => "Practitioner/#{author_id}" }
        },
        {
          "type" => { "coding" => [
            { "system" => "http://terminology.hl7.org/CodeSystem/provenance-participant-type",
              "code" => "enterer" }
          ] },
          "who" => { "reference" => "Practitioner/#{enterer_id}" },
          "onBehalfOf" => { "reference" => "Practitioner/#{author_id}" }
        }
      ]
    }.deep_merge(overrides.deep_stringify_keys)
  end

  # 承認: verifier の agent と署名を足したもの。
  def verification_agent(practitioner_id)
    {
      "type" => { "coding" => [
        { "system" => "http://terminology.hl7.org/CodeSystem/provenance-participant-type",
          "code" => "verifier" }
      ] },
      "who" => { "reference" => "Practitioner/#{practitioner_id}" }
    }
  end

  def verification_signature(practitioner_id)
    {
      "type" => [{ "system" => "urn:iso-astm:E1762-95:2013", "code" => "1.2.840.10065.1.12.1.5",
                   "display" => "Verification Signature" }],
      "when" => "2026-09-01T11:00:00+09:00",
      "who" => { "reference" => "Practitioner/#{practitioner_id}" }
    }
  end
end

RSpec.configure do |config|
  config.include ProvenancePayloadHelper, type: :request
end
