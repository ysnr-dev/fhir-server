module Fhir
  module ExtractionDefinitions
    module Provenance
      # Provenance.recorded は「いつ記録したか」(instant)。並べ替えと期間検索に使うので
      # 列に出す。target / agent は 0..* の参照で jsonb containment で引くため列を持たない
      # (SearchDefinitions::Provenance を参照)。
      FIELDS = {
        recorded: { path: "recorded", transform: :datetime }
      }.freeze

      # agent.type は agent 1 件につき 0..1 の CodeableConcept なので、配列を 1 段
      # 踏み越える dig_path + :codeable_concept_list で「どの agent の type でも引ける」。
      # signature.type は signature 1 件につき 1..* の Coding、つまり配列の中の配列なので
      # 専用の :coding_list_nested で 1 段ほどく。
      TOKENS = {
        "agent-type" => { path: "agent.type", kind: :codeable_concept_list },
        "signature-type" => { path: "signature.type", kind: :coding_list_nested }
      }.freeze
    end
  end
end
