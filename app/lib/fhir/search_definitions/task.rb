module Fhir
  module SearchDefinitions
    module Task
      PARAMS = {
        "identifier"       => { type: :identifier },
        "status"           => { type: :token, column: :status },
        "intent"           => { type: :token, column: :intent },
        "priority"         => { type: :token, column: :priority },
        # ワークフロー上の進捗は status(FHIR 固定の値セット)ではなく businessStatus
        # (施設ごとのコード)で表すため、両方を検索できるようにしている。
        "business-status"  => { type: :token, column: :business_status },
        # 1 オーダーから分割された複数 Task をまとめる業務識別子。
        "group-identifier" => { type: :token, column: :group_identifier },
        # Task.performerType(担当者の職種)。担当者そのものは owner。
        "performer"        => { type: :token, column: :performer_type },
        "code"             => { type: :token_or_text, token_column: :code,
                                 text_column: :code_text },
        # Task.for は「誰のための作業か」。FHIR の検索パラメータ名は subject で、
        # patient はその別名(Task.for が Patient を指す場合)。
        "subject"          => { type: :reference, column: :for_reference,
                                 target_type: "Patient", aliases: %w[patient] },
        "encounter"        => { type: :reference, column: :encounter_reference, target_type: "Encounter" },
        "requester"        => { type: :reference, column: :requester_reference, target_type: "Practitioner" },
        # 作業の割り当て先。「自分の未処理タスク」は owner + status で引く。
        "owner"            => { type: :reference, column: :owner_reference, target_type: "Practitioner" },
        # Task.focus は作業対象そのもの(ここでは実施中の ServiceRequest)。
        # basedOn(依頼元)と違い 0..1 なのでカラムで持つ。
        "focus"            => { type: :reference, column: :focus_reference, target_type: "ServiceRequest" },
        # 0..* references, so matched by jsonb containment rather than a column.
        # Task.basedOn はこの Task を生んだ依頼(ServiceRequest)を指す。オーダー側から
        # _revinclude=Task:based-on を添えると進捗を 1 リクエストで取得できる。
        "based-on"         => { type: :reference, multiple: true, jsonb_key: "basedOn",
                                 ref_path: %w[reference], target_type: "ServiceRequest" },
        # Task.partOf は親タスク。工程を段階に分けた場合の親子関係。
        "part-of"          => { type: :reference, multiple: true, jsonb_key: "partOf",
                                 ref_path: %w[reference], target_type: "Task" },
        "authored-on"      => { type: :datetime, column: :authored_on },
        # Task.lastModified。ワークリストの並べ替え(_sort=-modified)にも使う。
        "modified"         => { type: :datetime, column: :last_modified },
        # Task.executionPeriod。eq は期間の包含(重なりではない)。
        "period"           => { type: :datetime, column: :execution_period_start,
                                 end_column: :execution_period_end }
      }.freeze
    end
  end
end
