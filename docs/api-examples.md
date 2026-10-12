# 対応リソースとリソース別の例

## 対応リソース

全 37 リソースが同一のエンドポイント群（後述）を持ちます。

| カテゴリ | リソース |
|---|---|
| 基盤 | Patient / Practitioner / PractitionerRole / Organization / Location / Encounter |
| 薬剤 | Medication / MedicationRequest / MedicationDispense / MedicationAdministration / MedicationStatement |
| 検査・レポート | Observation / Specimen / ImagingStudy / DiagnosticReport / ServiceRequest |
| ワークフロー | Task |
| 来歴 | Provenance |
| 予約 | Appointment / Schedule / Slot |
| 臨床情報 | Condition / AllergyIntolerance / Procedure / Immunization / Flag |
| 診療計画 | CarePlan / Goal / CareTeam |
| 保険 | Coverage |
| 問診 | Questionnaire / QuestionnaireResponse |
| 文書 | Composition / DocumentReference / Binary |
| 関係者・機器 | RelatedPerson / Device |
| 集合 | Group |

`Binary` は既定では JSON 表現で返しますが、`Accept: application/pdf` など非 FHIR タイプを指定した
参照ではデコード済みの生コンテンツを元の `contentType` で返します。

正確な一覧と各リソースの検索パラメータは `GET /metadata`（CapabilityStatement）で確認できます。

**標準外の検索パラメータ**: `QuestionnaireResponse` / `Observation` の `problem` は
FHIR R4 に無いローカルの検索パラメータです。POS/POMR のカルテを 1 つのプロブレム（病名）で縦に読む
ための絞り込みで、base に対象疾患を表す要素が無いため、ルート直下の拡張
（`http://fhir-client.local/StructureDefinition/questionnaire-response-problem` /
`…/observation-problem`）の `valueReference` を引きます。`extension[]` は他の拡張と配列を
共有するので、参照だけでなく拡張の `url` も一致条件に含めています。`_include`/`_revinclude` では
辿れません（`Fhir::SearchReferences` には登録していないため）。

`Composition` / `QuestionnaireResponse` / `Observation` の `department` もローカルの検索パラメータです。
記録した診療科を `ServiceRequest` の依頼科と同じ拡張（`…/order-department`）から引くので、カルテを
診療科で絞り込むときにオーダーと記録を同じ値で検索できます。`Composition` の `ward` も同じ作りで、
記録した病棟(看護サマリなど)をオーダーの入院病棟と同じ拡張（`…/order-ward`）から引きます。

`QuestionnaireResponse` の `author-name` もローカルの検索パラメータです。JASPEHR の回答は記入者を
contained の `Practitioner`（氏名だけ）で持ち、`author` は `#practitioner` を指すため、`author` では
「この人が書いた回答」を引けません。氏名（`name[0].text`）から空白を除いた値を列に持ち、検索値も
同じく空白を除いて比べます（`author-name:exact=山田 太郎` は「山田太郎」「山田　太郎」にも一致）。
同姓同名は区別できません。

診療記録は標準の `Composition?entry=` で引けます。対象のプロブレムは C-CDA on FHIR
Progress Note の problems_section（LOINC 11450-4）の `section.entry` に入るためです。
`Composition.section[].entry[]` は配列の二重ネストなので、検索定義は `jsonb_key` に加えて
`nested_path`（要素の中でさらに辿る配列キー）を持ちます。

```bash
# 1 つのプロブレムに紐づく診療記録・オーダー
curl -s "http://localhost:3000/Composition?patient={patientId}&entry=Condition/{conditionId}"
curl -s "http://localhost:3000/ServiceRequest?reason-reference=Condition/{conditionId}&based-on:missing=true"
```

以下、`{Resource}` は上記いずれかに読み替えてください。

**インスタンス / タイプレベル**

| メソッド | パス | 説明 |
|---|---|---|
| `POST` | `/{Resource}` | 作成（`If-None-Exist` による条件付き作成対応） |
| `GET` | `/{Resource}/:id` | 参照 |
| `PUT` | `/{Resource}/:id` | 更新（`If-Match` 対応） |
| `PUT` | `/{Resource}?{criteria}` | 条件付き更新（upsert） |
| `PATCH` | `/{Resource}/:id` | 部分更新（JSON Patch, RFC 6902。`Content-Type: application/json-patch+json`） |
| `DELETE` | `/{Resource}/:id` | 削除（論理削除） |
| `DELETE` | `/{Resource}?{criteria}` | 条件付き削除（該当全件を削除。`conditionalDelete: "multiple"`） |
| `GET` | `/{Resource}` | 検索（Bundle）。チェーン検索（3 セグメントまでの多段対応）・`_has`・`_include`/`_revinclude`・`_sort`・`_count`（上限 500）/`_offset`・`_summary`/`_elements`・`_total`・`:missing`・`:not`（token / uri 型）・`Prefer: handling=strict` 等に対応 |
| `GET` | `/{Resource}/$distinct-dates` | 独自 operation: date 検索パラメータが取る値の重複なし集合（新しい順）。`date-param`（必須）・`precision=day\|full`・`timezone=±HH:MM`（既定はサーバーのローカルゾーン）・`limit`・`count=true`（日付ごとの件数） |
| `GET` | `/{Resource}/$next-identifier` | 独自 operation: `system`（必須）の identifier で次に使える番号を払い出す（`Parameters` の `value`）。数字だけの値を数値として比べ、払い出し済み・登録済み（削除済み含む）の最大値 + 1 を返す。同時に呼んでも同じ番号は返らない。登録の一部なので write スコープ |
| `GET` | `/{Resource}/_history` | タイプレベル履歴（`_count` / `_since` 対応）。検索パラメータを付けると、合致するリソース（削除済みを含む）の全版に絞る（例: `ServiceRequest/_history?based-on=ServiceRequest/X` でオーダー明細の履歴）。絞り込み時は通常の読み取りスコープで引け、未対応パラメータは 400。絞り込み無しは system スコープのみ |
| `GET` | `/{Resource}/:id/_history` | インスタンスのバージョン履歴（Bundle） |
| `GET` | `/{Resource}/:id/_history/:vid` | 特定バージョンの参照（vread） |
| `POST` | `/{Resource}/$validate` | 保存せずバリデーションのみ実行 |

**システムレベル / オペレーション**

| メソッド | パス | 説明 |
|---|---|---|
| `POST` | `/` | Bundle 一括処理（transaction / batch） |
| `GET` | `/_history` | システムレベル履歴（全リソース横断） |
| `GET` | `/Patient/:id/$everything` | 患者コンパートメント一括取得（`_type` / `_since` 対応） |
| `GET` | `/AuditEvent` | アクセス監査ログの検索（読み取り専用。`date` / `agent` / `subtype` / `entity` / `entity-type` で絞り込み） |
| `GET` | `/AuditEvent/:id` | 監査ログの参照 |
| `GET` | `/metadata` | CapabilityStatement |
| `GET` | `/.well-known/smart-configuration` | SMART ディスカバリ文書 |
| `POST` | `/oauth/token` | アクセストークン発行（認証有効時に使用） |

すべての FHIR リクエスト（認証拒否 401/403 を含む）は AuditEvent として自動記録されます。
記録には操作種別・対象リソース・結果ステータス・認証クライアント（匿名アクセスは anonymous）が含まれ、
API からは読み取り専用です。認証有効時、監査ログの参照には `system/AuditEvent.read` 相当のスコープが必要です。

## Patient の例

**作成**

```bash
curl -i -X POST http://localhost:3000/Patient \
  -H 'Content-Type: application/fhir+json' \
  -d '{
    "resourceType": "Patient",
    "identifier": [
      { "system": "urn:oid:1.2.392.100495.20.3.51", "value": "12345" }
    ],
    "name": [
      { "use": "official", "family": "山田", "given": ["太郎"] },
      {
        "extension": [{
          "url": "http://hl7.org/fhir/StructureDefinition/iso21090-EN-representation",
          "valueCode": "SYL"
        }],
        "family": "ヤマダ", "given": ["タロウ"]
      }
    ],
    "gender": "male",
    "birthDate": "1990-01-01"
  }'
```

レスポンスの `id` を控えておき、以降の参照・更新・削除に使用します。

**参照 / 更新 / 削除**

```bash
curl -s http://localhost:3000/Patient/{id}

curl -i -X PUT http://localhost:3000/Patient/{id} \
  -H 'Content-Type: application/fhir+json' \
  -H 'If-Match: W/"1"' \
  -d '{ "resourceType": "Patient", "identifier": [...], "gender": "female" }'

curl -i -X DELETE http://localhost:3000/Patient/{id}
```

**検索**

```bash
# identifier（system|value または value のみ）
curl -s "http://localhost:3000/Patient?identifier=12345"

# 氏名（漢字・カナどちらも部分一致）
curl -G -s "http://localhost:3000/Patient" --data-urlencode "name=ヤマダ"

# gender / birthdate（プレフィックス ge/le/gt/lt 対応）/ ページング
curl -s "http://localhost:3000/Patient?gender=male&birthdate=ge1980-01-01&_count=20&_offset=0"
```

**必須項目（JP-Core）**: `identifier`（1件以上）。任意項目のバリデーション: `gender` の値セット、
`birthDate` の書式（`YYYY`/`YYYY-MM`/`YYYY-MM-DD`）。

---

## MedicationRequest の例

`subject` は既存の `Patient/{id}` を参照する必要があります（実在しない場合は 422）。

**作成**

```bash
curl -i -X POST http://localhost:3000/MedicationRequest \
  -H 'Content-Type: application/fhir+json' \
  -d '{
    "resourceType": "MedicationRequest",
    "identifier": [
      { "system": "http://jpfhir.jp/fhir/core/mhlw/IdSystem/Medication-RPGroupNumber", "value": "1" },
      { "system": "http://jpfhir.jp/fhir/core/mhlw/IdSystem/MedicationAdministrationIndex", "value": "1" }
    ],
    "status": "active",
    "intent": "order",
    "medicationCodeableConcept": {
      "coding": [{ "system": "urn:oid:1.2.392.100495.20.2.74", "code": "620004422", "display": "アムロジピン錠5mg" }],
      "text": "アムロジピン錠5mg"
    },
    "subject": { "reference": "Patient/{patientId}" },
    "authoredOn": "2026-07-19T10:00:00+09:00"
  }'
```

**検索**

```bash
# 対象患者で絞り込み
curl -s "http://localhost:3000/MedicationRequest?subject=Patient/{patientId}"

# ステータス・薬剤コードで絞り込み
curl -s "http://localhost:3000/MedicationRequest?status=active&code=620004422"
```

**必須項目（JP-Core）**: `status`、`intent`、`medicationCodeableConcept`（`medicationReference` は非対応）、
`subject`（実在する Patient への参照）、`authoredOn`。`identifier` は1件以上必須（rpNumber/orderInRp の
2スライスが揃っていない場合は拒否せず warning issue を返す）。

---

## ServiceRequest の例

`subject` が `Patient/{id}` 参照の場合のみ実在確認を行います（`Location/...` 等の参照は素通しします）。
`identifier` は必須ではありません。

**作成**

```bash
curl -i -X POST http://localhost:3000/ServiceRequest \
  -H 'Content-Type: application/fhir+json' \
  -d '{
    "resourceType": "ServiceRequest",
    "status": "active",
    "intent": "order",
    "code": {
      "coding": [{ "system": "http://snomed.info/sct", "code": "396550006", "display": "血液検査" }],
      "text": "血液検査"
    },
    "subject": { "reference": "Patient/{patientId}" },
    "authoredOn": "2026-07-19T10:00:00+09:00"
  }'
```

**検索**

```bash
curl -s "http://localhost:3000/ServiceRequest?subject=Patient/{patientId}&status=active"

# 依頼先で絞る（他科依頼の依頼先診療科。型を省いた id は Organization とみなす）
curl -s "http://localhost:3000/ServiceRequest?performer=Organization/{deptId}&status=active&_include=ServiceRequest:performer"

# 1 回の発行でまとめて出したオーダー（オーダーセット・レジメン適用）を requisition で束ねて引く
curl -s "http://localhost:3000/ServiceRequest?requisition=urn:ietf:rfc:3986|urn:uuid:{requisitionId}"

# ある日に効いている継続的な指示（看護指示・食事・リハビリ・栄養指導）。開始は occurrenceDateTime、
# 終了は fhir-client のローカル拡張 *-order-end。終了の無い指示は継続中として掛かる
curl -s "http://localhost:3000/ServiceRequest?patient={patientId}&order-period=ge2026-09-09&order-period=le2026-09-09"
```

**主な検索パラメータ**: `identifier` / `status` / `intent` / `category` / `code` / `subject`（別名 `patient`）/
`encounter` / `requester` / `performer` / `requisition` / `authoredon` / `occurrence`（`occurrenceDateTime`）/
`based-on` / `reason-reference`、ローカル拡張を引く `department` / `ward`（`order-department` / `order-ward`）と
`order-period`（開始 = `occurrenceDateTime`、終了 = `nursing-order-end` / `meal-order-end` / `rehab-order-end` /
`nutrition-guidance-order-end` 拡張。期間検索の意味論は `Encounter.date` と同じで、`eq` は包含、
`ge`+`le` で重なり、終了なしは開いた区間）。

**必須項目（JP-Core）**: `status`（値セット `draft|active|on-hold|revoked|completed|entered-in-error|unknown`）、
`intent`（値セット `proposal|plan|directive|order|original-order|reflex-order|filler-order|instance-order|option`）、
`subject`。

---

## Procedure の `date` 検索

`Procedure.performed[x]` は期間として索引します。`performedDateTime`（放射線・処置の実施記録）は
開始 = 終了の点、`performedPeriod`（手術）は開始・終了（終了が無ければ進行中）です。
意味論は `Encounter.date` と同じで、`date=2026-08-28` は包含（日をまたぐ手術はどちらの日にも含まれない）、
その日に掛かる手術は `date=ge2026-08-28&date=le2026-08-28` で引きます。`_sort=date` は開始で並びます。

---

## Task の例（ServiceRequest のワークフロー管理）

`ServiceRequest` が「何を依頼したか」を表すのに対し、`Task` は「その依頼が今どこまで進んだか」を表します。
JP Core は `Task` をプロファイルしていないため、基底の FHIR R4 定義に対する手書きバリデータのみが働きます
（`Composition` / `Group` と同じ扱い）。

依頼と Task の結び付けは 2 つの要素で行います。

| 要素 | 意味 | 検索パラメータ |
|---|---|---|
| `focus` | 作業の対象そのもの（0..1） | `focus` |
| `basedOn` | この作業を生んだ依頼（0..*） | `based-on` |

進捗は 2 系統で持ちます。`status` は FHIR 固定の値セット
（`draft|requested|received|accepted|rejected|ready|cancelled|in-progress|on-hold|failed|completed|entered-in-error`）、
`businessStatus` は施設ごとの工程コードです。`Task.for` は「誰のための作業か」で、
これがある Task だけが患者コンパートメント（`Patient/$everything` / `Patient/$export` /
患者コンテキストのトークン）に入ります。無い場合は作成自体は成功しますが warning を返します。

**作成**

```bash
curl -i -X POST http://localhost:3000/Task \
  -H 'Content-Type: application/fhir+json' \
  -d '{
    "resourceType": "Task",
    "identifier": [{ "system": "http://example.org/task", "value": "TSK1" }],
    "groupIdentifier": { "system": "http://example.org/order-group", "value": "ORD-2026-0001" },
    "status": "in-progress",
    "businessStatus": {
      "coding": [{ "system": "http://example.org/CodeSystem/lab-workflow", "code": "collected" }],
      "text": "検体採取済"
    },
    "intent": "order",
    "priority": "routine",
    "code": { "coding": [{ "system": "http://hl7.org/fhir/CodeSystem/task-code", "code": "fulfill" }] },
    "focus": { "reference": "ServiceRequest/{serviceRequestId}" },
    "basedOn": [{ "reference": "ServiceRequest/{serviceRequestId}" }],
    "for": { "reference": "Patient/{patientId}" },
    "owner": { "reference": "Practitioner/{practitionerId}" },
    "authoredOn": "2026-08-12T09:00:00+09:00",
    "lastModified": "2026-08-12T10:30:00+09:00",
    "executionPeriod": { "start": "2026-08-12T09:30:00+09:00", "end": "2026-08-12T10:30:00+09:00" }
  }'
```

**検索**

```bash
# 担当者の未処理ワークリスト（更新の新しい順）
curl -s "http://localhost:3000/Task?owner=Practitioner/{practitionerId}&status=in-progress&_sort=-modified"

# 施設独自の工程コードで絞る
curl -s "http://localhost:3000/Task?business-status=http://example.org/CodeSystem/lab-workflow|collected"

# オーダーとその進捗を 1 リクエストで（オーダー画面の典型形）
curl -s "http://localhost:3000/ServiceRequest?_id={serviceRequestId}&_revinclude=Task:based-on"

# 進行中の Task があるオーダーだけを引く
curl -s "http://localhost:3000/ServiceRequest?_has:Task:focus:status=in-progress"
```

**主な検索パラメータ**: `identifier` / `status` / `intent` / `priority` / `business-status` /
`group-identifier` / `performer`（`performerType`）/ `code` / `subject`（別名 `patient`、`Task.for`）/
`encounter` / `requester` / `owner` / `focus` / `based-on` / `part-of` / `authored-on` /
`modified`（`lastModified`）/ `period`（`executionPeriod`）。

**必須項目（FHIR R4）**: `status`、`intent`（値セットは request-intent に `unknown` を加えたもの）。
加えて invariant `inv-1`（`lastModified` は `authoredOn` 以降）を検証します。

---

## Provenance の例（代行入力・承認）

「この記録を誰が入力し、誰の指示によるもので、誰が承認したか」を、対象のリソースを書き換えずに残します。
医師以外が医師の指示でオーダーを入力する**代行入力**と、指示医師が後から確認する**承認**の両方を
`Provenance` 1 種で表します（JP Core は `Provenance` をプロファイルしていないので、基底 FHIR R4 に
対する手書きバリデータのみが働きます）。

| 要素 | 意味 |
|---|---|
| `target` | この活動が生んだ・更新したリソース（1..*、異種可）。オーダーなら `ServiceRequest` とその明細 |
| `recorded` | 記録した日時（instant、必須）|
| `agent[].type` | 役割。`author`＝指示した人、`enterer`＝入力した本人、`verifier`＝承認した人 |
| `agent[].who` | その人（`Practitioner` など）|
| `agent[].onBehalfOf` | 代行入力で「誰の指示か」を指す |
| `signature[]` | 承認の署名（`type` / `when` / `who` が必須）|

代行入力の記録:

```bash
curl -X POST http://localhost:3000/Provenance \
  -H 'Content-Type: application/fhir+json' -d '{
    "resourceType": "Provenance",
    "target": [{ "reference": "ServiceRequest/<order-id>" }],
    "recorded": "2026-09-01T10:30:15+09:00",
    "agent": [
      { "type": { "coding": [{ "system": "http://terminology.hl7.org/CodeSystem/provenance-participant-type",
                               "code": "author" }] },
        "who": { "reference": "Practitioner/<doctor-id>" } },
      { "type": { "coding": [{ "system": "http://terminology.hl7.org/CodeSystem/provenance-participant-type",
                               "code": "enterer" }] },
        "who": { "reference": "Practitioner/<clerk-id>" },
        "onBehalfOf": { "reference": "Practitioner/<doctor-id>" } }
    ]
  }'
```

承認は、この `Provenance` に `verifier` の `agent` と `signature` を足して `PUT` します。

検索:

```bash
# そのオーダーの来歴
curl 'http://localhost:3000/Provenance?target=ServiceRequest/<order-id>'
# オーダー本体と一緒に引く（画面はこちらを使う）
curl 'http://localhost:3000/ServiceRequest?_id=<order-id>&_revinclude=Provenance:target'
# 承認済みのオーダーだけ
curl 'http://localhost:3000/ServiceRequest?_has:Provenance:target:agent-type=http://terminology.hl7.org/CodeSystem/provenance-participant-type|verifier'
```

**主な検索パラメータ**: `target`（0..* の異種参照。型を省いた id は `ServiceRequest` とみなします）/
`patient`（`target` のうち `Patient` を指すもの）/ `agent`（`agent[].who`）/ `agent-type` /
`signature-type` / `recorded`。`_sort` が効くのは `recorded` だけです。

**必須項目（FHIR R4）**: `target`（1..*、各要素に `reference`）、`recorded`（instant）、
`agent`（1..*、各要素に `who.reference`）。`signature` を入れるなら `type` / `when` / `who` が必須、
`entity` を入れるなら `role`（値セット必須）/ `what.reference` が必須です。`agent.type` は
extensible binding なので、値セットを外れても警告のみで受理します。

**制約**:

- **患者コンパートメントに入りません**。`target` が 0..* なので `Fhir::PatientCompartment`（単一値の
  `Patient` 参照列だけを見る）の対象外で、`Group` / `Binary` と同じくシステムスコープでのみ読めます。
  `Patient/$everything` にも含まれません。将来これを変えるなら、`target` に必ず `Patient` を含める規約に
  したうえで `patient_reference` 列を抽出する必要があります（`Appointment` と同じ手）。
- **バージョン付き参照（`ServiceRequest/1/_history/2`）は引けません**。このサーバーの参照検索と
  `_include` は文字列の完全一致なので、`?target=ServiceRequest/1` からも `_revinclude` からも外れます。
  POST は通りますが警告を返すので、バージョンを持たない参照を格納してください。
- `_revinclude=Provenance:target` で逆引きできる型は `Fhir::SearchReferences::MAP` の `targets:` に
  挙げたものだけです（挙げ忘れた型は静かに 0 件になります）。

---

## Appointment / Schedule / Slot の例（予約）

予約は 3 リソースの組で表します。JP Core はいずれもプロファイルしていないため、基底の FHIR R4 定義に
対する手書きバリデータのみが働きます（`Composition` / `Group` / `Task` と同じ扱い）。

| リソース | 意味 | 主な参照 |
|---|---|---|
| `Schedule` | 担当医・診察室ごとの「枠表」。いつの期間の枠を提供するか | `actor`（1..*、Practitioner / Location など） |
| `Slot` | 枠表の中の個々の時間枠。空きかどうかを `status` が持つ | `schedule`（1..1） |
| `Appointment` | 枠を押さえた予約そのもの | `slot`（0..*）、`participant.actor`（1..*） |

`Appointment` には患者を指す単一の要素がありません（患者は `participant` の 1 人）。このサーバーは
`participant.actor` のうち Patient を指すものを 1 件取り出して索引しており、それがある予約だけが
患者コンパートメント（`Patient/$everything` / `Patient/$export` / 患者コンテキストのトークン）に入ります。
無い場合（枠止め・院内会議など）は作成自体は成功しますが warning を返します。

**作成（枠表 → 枠 → 予約）**

```bash
# 1. 診療枠（枠表）
curl -i -X POST http://localhost:3000/Schedule \
  -H 'Content-Type: application/fhir+json' \
  -d '{
    "resourceType": "Schedule",
    "identifier": [{ "system": "http://example.org/schedule", "value": "SCH1" }],
    "active": true,
    "serviceType": [{ "coding": [{ "system": "http://example.org/CodeSystem/service-type", "code": "outpatient" }], "text": "一般外来" }],
    "specialty": [{ "coding": [{ "system": "http://snomed.info/sct", "code": "419192003" }], "text": "内科" }],
    "actor": [{ "reference": "Practitioner/{practitionerId}" }],
    "planningHorizon": { "start": "2026-09-01T00:00:00+09:00", "end": "2026-09-30T23:59:59+09:00" }
  }'

# 2. 予約可能な時間枠（start / end は instant。タイムゾーン必須）
curl -i -X POST http://localhost:3000/Slot \
  -H 'Content-Type: application/fhir+json' \
  -d '{
    "resourceType": "Slot",
    "schedule": { "reference": "Schedule/{scheduleId}" },
    "status": "free",
    "appointmentType": { "coding": [{ "system": "http://terminology.hl7.org/CodeSystem/v2-0276", "code": "ROUTINE" }] },
    "start": "2026-09-01T09:00:00+09:00",
    "end": "2026-09-01T09:30:00+09:00"
  }'

# 3. 予約（枠を押さえたら Slot.status は busy に更新する）
curl -i -X POST http://localhost:3000/Appointment \
  -H 'Content-Type: application/fhir+json' \
  -d '{
    "resourceType": "Appointment",
    "identifier": [{ "system": "http://example.org/appointment", "value": "APT1" }],
    "status": "booked",
    "appointmentType": { "coding": [{ "system": "http://terminology.hl7.org/CodeSystem/v2-0276", "code": "ROUTINE" }] },
    "description": "内科 再診",
    "start": "2026-09-01T09:00:00+09:00",
    "end": "2026-09-01T09:30:00+09:00",
    "minutesDuration": 30,
    "slot": [{ "reference": "Slot/{slotId}" }],
    "participant": [
      { "actor": { "reference": "Patient/{patientId}" }, "required": "required", "status": "accepted" },
      { "actor": { "reference": "Practitioner/{practitionerId}" }, "required": "required", "status": "accepted" }
    ]
  }'
```

**検索**

```bash
# 空き枠を探す（予約画面の中心的なクエリ）。start を 2 回並べると AND で期間になる
curl -s "http://localhost:3000/Slot?schedule=Schedule/{scheduleId}&status=free&start=ge2026-09-01&start=lt2026-09-02&_sort=start"

# その患者のその日の予約
curl -s "http://localhost:3000/Appointment?patient=Patient/{patientId}&date=ge2026-09-01&date=lt2026-09-02"

# 担当医の予約一覧 / 診察室の予約一覧（どちらも participant.actor を参照先の型で切り分ける）
curl -s "http://localhost:3000/Appointment?practitioner=Practitioner/{practitionerId}&status=booked"
curl -s "http://localhost:3000/Appointment?location=Location/{locationId}&date=ge2026-09-01"

# 患者の承諾待ちの予約（status ではなく participant.status で持つ）
curl -s "http://localhost:3000/Appointment?part-status=needs-action"

# 枠と、その枠を埋めている予約を 1 リクエストで
curl -s "http://localhost:3000/Slot?schedule=Schedule/{scheduleId}&_revinclude=Appointment:slot"

# 予約と参加者（患者・担当医・診察室）を 1 リクエストで
curl -s "http://localhost:3000/Appointment?date=ge2026-09-01&_include=Appointment:actor"

# 空き枠が残っている枠表だけを引く
curl -s "http://localhost:3000/Schedule?active=true&_has:Slot:schedule:status=free"
```

**主な検索パラメータ**

| リソース | パラメータ |
|---|---|
| `Schedule` | `identifier` / `active` / `actor` / `date`（`planningHorizon`。期間の包含）/ `service-category` / `service-type` / `specialty` |
| `Slot` | `identifier` / `status` / `schedule` / `start` / `appointment-type` / `service-category` / `service-type` / `specialty` |
| `Appointment` | `identifier` / `status` / `appointment-type` / `service-category` / `service-type` / `specialty` / `reason-code` / `part-status` / `patient` / `actor`（別名 `practitioner`）/ `location` / `slot` / `based-on` / `reason-reference` / `date`（`Appointment.start`） |

R4 が `Slot.end` / `Appointment.end` に検索パラメータを定めていないため、期間の指定は
`start`（`Slot`）・`date`（`Appointment`）を 2 回並べた AND で表します。

**必須項目（FHIR R4）**

- `Schedule`: `actor`（1..*）。`planningHorizon` は `end` が `start` 以降であること。
- `Slot`: `status`（値セット `busy|free|busy-unavailable|busy-tentative|entered-in-error`）、`schedule`、
  `start`、`end`。`start` / `end` は `instant` なのでタイムゾーン付きの完全な ISO8601 のみ受け付け、
  `end` は `start` より後であること。
- `Appointment`: `status`（値セット `proposed|pending|booked|arrived|fulfilled|cancelled|noshow|
  entered-in-error|checked-in|waitlist`）、`participant`（1..*、各要素の `status` は
  `accepted|declined|tentative|needs-action`）。加えて invariant `app-1`（`participant` は `type` か
  `actor` のいずれかが必要）、`app-2`（`start` と `end` は両方あるか両方無いか）、`app-3`（`start` /
  `end` を省略できるのは `proposed` / `cancelled` / `waitlist` のみ）、`app-4`（`cancelationReason` は
  `cancelled` / `noshow` のときだけ）を検証します。

---

## CarePlan / Goal の例（診療計画・クリニカルパス）

`CarePlan` が「何をする計画か」、`Goal` が「その計画で何を達成したいか（と達成できたか）」を表します。
JP Core はどちらもプロファイルしていないため、基底の FHIR R4 定義に対する手書きバリデータのみが働きます
（`Composition` / `Group` / `Task` と同じ扱い）。

**計画の入れ子**: クリニカルパス（[ePath](https://e-path.jp/fhir/ePath/)）のように段階のある計画は、
`CarePlan` の木で表します。`partOf` に**祖先すべて**を並べる約束にすると、次の 2 つの検索だけで
木を出し入れできます。

| 引きたいもの | 検索 |
|---|---|
| 木の根（適用そのもの）だけ | `part-of:missing=true` |
| ある根の子孫すべて | `part-of=CarePlan/{根の id}` |

`ServiceRequest` のヘッダを `based-on:missing=true` で引くのと同じ形です。

```bash
# 適用（木の根）
curl -i -X POST http://localhost:3000/CarePlan   -H 'Content-Type: application/fhir+json'   -d '{
    "resourceType": "CarePlan",
    "identifier": [{ "system": "http://example.org/pathway-apply", "value": "1311234567.ap-001" }],
    "status": "active",
    "intent": "plan",
    "title": "腹腔鏡下胆嚢摘出術（4泊5日）",
    "subject": { "reference": "Patient/{patientId}" },
    "encounter": { "reference": "Encounter/{encounterId}" },
    "instantiatesUri": ["http://fhir-client.local/pathway/900001"],
    "period": { "start": "2026-09-01" }
  }'

# 病日（子）。partOf に根を並べる
curl -i -X POST http://localhost:3000/CarePlan   -H 'Content-Type: application/fhir+json'   -d '{
    "resourceType": "CarePlan", "status": "active", "intent": "plan", "title": "入院日",
    "subject": { "reference": "Patient/{patientId}" },
    "partOf": [{ "reference": "CarePlan/{applyId}" }],
    "goal": [{ "reference": "Goal/{goalId}" }]
  }'
```

**主な検索パラメータ**

| リソース | パラメータ | 対象 |
|---|---|---|
| `CarePlan` | `identifier` / `status` / `intent` / `category` | `category` は 0..* なので全 coding を索引（先頭に依存しない） |
| | `subject`（別名 `patient`） / `encounter` | |
| | `date` | `CarePlan.period`。`eq` は包含で、`end` が無ければ継続中 |
| | `part-of` / `goal` | 0..* 参照。`_include=CarePlan:goal` で目標まで 1 リクエスト |
| | `condition` | `CarePlan.addresses`（扱う問題）。`_include=CarePlan:condition` で問題まで 1 リクエスト |
| | `instantiates-canonical` / `instantiates-uri` | 元にした定義（このサーバーの外にある定義は uri） |
| `Goal` | `identifier` / `lifecycle-status` / `achievement-status` / `category` | |
| | `subject`（別名 `patient`） / `start-date` | |

`Goal` から `CarePlan` への逆参照は R4 に無いので、辿る向きは `CarePlan` → `Goal` だけです。
実施記録（`Procedure`）は `basedOn` で計画を指せるので、`_revinclude=Procedure:based-on` を添えると
「その計画が実施されたか」まで同じ応答で揃います。

**必須項目（FHIR R4）**

- `CarePlan`: `status`（値セット `draft|active|on-hold|revoked|completed|entered-in-error|unknown`）、
  `intent`（値セット `proposal|plan|order|option`）、`subject`。`Patient/{id}` は実在を確認し、
  `Group` を指す計画は患者コンパートメントに入りません。`partOf` / `goal` は配列であること
  （jsonb 包含で引くため、配列でないと静かに引けなくなります）。
- `Goal`: `lifecycleStatus`（値セット `proposed|planned|accepted|active|on-hold|completed|cancelled|
  entered-in-error|rejected`）、`description`、`subject`。
  `achievementStatus` の束縛は **preferred** なので、ePath の達成状態（`1` 達成 / `2` 未達成（バリアンス）/
  `3` 未評価）のようにガイド独自のコード体系を使えます（形だけを検証し、値は縛りません）。

---

## Practitioner / Organization の例

JP-Core上、両リソースとも**必須項目はほぼありません**（Practitionerは全項目任意、Organizationのみ
`identifier` または `name` の少なくとも一方が必要という制約があります）。

**Practitioner 作成**

```bash
curl -i -X POST http://localhost:3000/Practitioner \
  -H 'Content-Type: application/fhir+json' \
  -d '{
    "resourceType": "Practitioner",
    "identifier": [{ "system": "http://jpfhir.jp/fhir/core/mhlw/IdSystem/medicalRegistrationNumber", "value": "12345" }],
    "name": [{ "use": "official", "family": "鈴木", "given": ["一郎"] }],
    "gender": "male",
    "birthDate": "1980-01-01"
  }'
```

**Organization 作成**（`identifier`/`name` のどちらか一方があれば作成可能）

```bash
curl -i -X POST http://localhost:3000/Organization \
  -H 'Content-Type: application/fhir+json' \
  -d '{ "resourceType": "Organization", "name": "サンプル病院", "active": true }'
```

**必須項目（JP-Core）**:
- Practitioner: なし（`gender`/`birthDate` は値がある場合のみ書式検証）
- Organization: `identifier` または `name` の少なくとも一方（org-1制約、両方欠落は422）

---

## Questionnaire / QuestionnaireResponse の例（JASPEHR）

問診票・診療テンプレートは JASPEHR IG v1.0.0 のプロファイルに準拠します。

**Questionnaire の作成**

```bash
curl -i -X POST http://localhost:3000/Questionnaire \
  -H 'Content-Type: application/fhir+json' \
  -d '{
    "resourceType": "Questionnaire",
    "url": "http://example.org/Questionnaire/jaspehr-example",
    "version": "1.0.0",
    "name": "ExampleQ",
    "title": "問診票サンプル",
    "status": "active",
    "subjectType": ["Patient"],
    "date": "2026-07-29T10:00:00+09:00",
    "item": [
      {
        "linkId": "group1",
        "type": "group",
        "text": "基本情報",
        "item": [
          { "linkId": "q1", "type": "string", "text": "主訴" },
          { "linkId": "q2", "type": "integer", "text": "発症からの日数" }
        ]
      }
    ]
  }'
```

**必須項目（JASPEHR）**: `version` / `name` / `title` / `status` / `subjectType` / `item`（1件以上）と、
各 item の `linkId` / `type`。

**JASPEHR 固有の制約**（違反は 422。カッコ内は IG の invariant キー）:

- `name` は半角英数字と一部記号のみ・**15文字以内**（jsp-5）。`item.linkId` も同じ文字種（jsp-4 / jsr-1）
- `item.type` は `group` / `display` / `decimal` / `integer` / `date` / `dateTime` / `time` / `string` /
  `text` / `choice` のみ（基底 R4 から `boolean` / `url` / `open-choice` / `attachment` / `reference` /
  `quantity` を除外）
- `enableWhen` / `repeats` を持てるのは `type = group` の item のみ（jsp-1 / jsp-3）。両方の同時指定は不可（jsp-8）
- `type = choice` の item には `questionnaire-itemControl` 拡張が必須（jsp-6）。その子 item は全て
  `enableWhen` を持ち（jsp-9）、`enableWhen.question` は親の `linkId` と一致すること（jsp-2）
- `repeats = true` の item には `questionnaire-maxOccurs` 拡張が必須（jsp-10）
- `initialExpression` と `calculatedExpression` の同時指定は不可（jsp-7）

**QuestionnaireResponse の作成**

`subject` は実在する `Patient/{id}` を参照する必要があります（他の型・不在は 422）。

```bash
curl -i -X POST http://localhost:3000/QuestionnaireResponse \
  -H 'Content-Type: application/fhir+json' \
  -d '{
    "resourceType": "QuestionnaireResponse",
    "extension": [{
      "url": "http://jpfhir.jp/fhir/clins/Extension/StructureDefinition/JP_eCS_InstitutionNumber",
      "valueIdentifier": {
        "system": "http://jpfhir.jp/fhir/core/IdSystem/insurance-medical-institution-no",
        "value": "1311234567"
      }
    }],
    "identifier": { "system": "http://example.org/questionnaire-response", "value": "1311234567^P0001^R0001" },
    "questionnaire": "http://example.org/Questionnaire/jaspehr-example|1.0.0",
    "status": "completed",
    "subject": { "reference": "Patient/{patientId}" },
    "authored": "2026-07-29T10:00:00+09:00",
    "author": { "reference": "Practitioner/{practitionerId}" },
    "item": [
      { "linkId": "group1", "item": [
        { "linkId": "q1", "answer": [{ "valueString": "腹痛" }] },
        { "linkId": "q2", "answer": [{ "valueInteger": 3 }] }
      ]}
    ]
  }'
```

**必須項目（JASPEHR）**: `identifier` / `questionnaire` / `status` / `subject` / `authored` / `author`（すべて 1..1）。

- `identifier.value` は `保険医療機関番号 ^ 被保険者個人識別子 ^ 報告単位ID` の**キャレット区切り3要素**
- `status` は 新規=`completed` / 更新=`amended` / 削除=`stopped`
- `questionnaire` は Reference ではなく **canonical**（`{Questionnaire.url}|{version}` 形式の絶対 URL）。
  参照先がこのサーバーに存在するかは検証しません（外部 IG の canonical を指しうるため）
- `author` は `Practitioner/{id}` または contained 参照（`#practitioner`）。存在確認はしません
- JP eCS の医療機関番号拡張を付ける場合、値は 2桁都道府県 + 1桁点数表区分(1〜3) + 7桁医療機関コードの
  計10桁であること

**検索**

```bash
# url / questionnaire（canonical）は完全一致。前方一致では引けません
curl -G -s http://localhost:3000/Questionnaire \
  --data-urlencode "url=http://example.org/Questionnaire/jaspehr-example"

curl -s "http://localhost:3000/Questionnaire?status=active&subject-type=Patient&version=1.0.0"

curl -G -s http://localhost:3000/QuestionnaireResponse \
  --data-urlencode "questionnaire=http://example.org/Questionnaire/jaspehr-example|1.0.0"

# 患者・作成者・記入日時で絞り込み（QuestionnaireResponse は患者コンパートメントに入るため
# Patient/$everything や patient/*.read スコープの対象にもなります）
curl -s "http://localhost:3000/QuestionnaireResponse?patient={patientId}&status=completed"
curl -s "http://localhost:3000/QuestionnaireResponse?author={practitionerId}&authored=ge2026-07-01"
```

> `Questionnaire` 自体は患者情報を含まない定義系リソースのため、対話型 launch の患者スコープでも
> 全件参照できます（`Medication` / `Location` と同じ扱い）。

---

## Bundle（一括処理）の例

`POST /` に `Bundle` リソース（`type: "transaction"` または `"batch"`）を送信すると、複数リソースへの操作を
一括実行できます。

| type | 挙動 |
|---|---|
| `transaction` | 全件成功 or 全件ロールバック（原子的）。同一 Bundle 内で作成する別リソースを `urn:uuid` 参照で相互参照可能 |
| `batch` | 各エントリを独立処理。部分成功可（一部が失敗しても他は確定） |

`entry[].request` に `method`（`POST`/`GET`/`PUT`/`DELETE`）と `url`（`Patient` / `Patient/{id}` /
`Patient?identifier=...` など）を指定します。

**transaction: Patient と、それを参照する ServiceRequest を同時作成**

`urn:uuid:p1` のような `fullUrl` を付けておくと、同一 Bundle 内の他エントリからその ID 確定前に参照でき、
サーバー側で実際に採番された `Patient/{id}` へ自動的に解決されます。

```bash
curl -i -X POST http://localhost:3000/ -H 'Content-Type: application/fhir+json' -d '{
  "resourceType": "Bundle",
  "type": "transaction",
  "entry": [
    {
      "fullUrl": "urn:uuid:p1",
      "resource": { "resourceType": "Patient", "identifier": [{ "system": "urn:oid:1.2.392.100495.20.3.51", "value": "B1" }] },
      "request": { "method": "POST", "url": "Patient" }
    },
    {
      "resource": { "resourceType": "ServiceRequest", "status": "active", "intent": "order", "subject": { "reference": "urn:uuid:p1" } },
      "request": { "method": "POST", "url": "ServiceRequest" }
    }
  ]
}'
# => 200 "transaction-response"。ServiceRequest.subject.reference は "Patient/{採番されたid}" に解決される
```

いずれかのエントリが失敗（400/404/422等）すると、**それまでに成功した操作も含めて全てロールバック**され、
失敗したエントリの `OperationOutcome`（`expression` に `Bundle.entry[N]` を含む）が単一で返されます。

`PUT` / `PATCH` のエントリは `request.ifMatch`（`W/"3"` の形の ETag）で楽観ロックできます。版が合わなければ
そのエントリが 412 になり、transaction 全体がロールバックされます。

**batch: 複数操作を独立実行（部分成功あり）**

```bash
curl -i -X POST http://localhost:3000/ -H 'Content-Type: application/fhir+json' -d '{
  "resourceType": "Bundle",
  "type": "batch",
  "entry": [
    { "resource": { "resourceType": "Patient", "identifier": [{ "system": "urn:oid:1.2.392.100495.20.3.51", "value": "B2" }] },
      "request": { "method": "POST", "url": "Patient" } },
    { "request": { "method": "GET", "url": "Patient/does-not-exist" } }
  ]
}'
# => 200 "batch-response"。1件目は201相当で成功、2件目は404相当だが1件目の結果はロールバックされない
```

---

## Bulk Data $export（一括エクスポート）の例

[Bulk Data Access IG v2.0.0](http://hl7.org/fhir/uv/bulkdata/) に準拠した非同期エクスポート。
システム全体（`/$export`）、全患者コンパートメント（`/Patient/$export`）、または特定コホートの
患者コンパートメント（`/Group/{id}/$export`）を NDJSON で取得できます。
`Prefer: respond-async` ヘッダーが必須です。

`Group/$export` は `Group.member[].entity` のうち `Patient/{id}` を指すものだけを解決対象とします。
`inactive: true` が付いたメンバーと、グループ作成後に削除された患者は除外されます
（`member.period` は評価しません。Bulk Data IG に時点メンバーシップの定義が無いためです）。
Patient 以外のメンバー（Practitioner / Device など）は無視されます。メンバーが 1 人も解決できない
コホートはエラーではなく、`"output": []` の完了マニフェストを返します。
`Group` リソース自体は患者コンパートメントを持たないため出力には含まれません。
認可は対象リソース型の読み取りスコープに加えて、名簿を解決するための `Group.read` が必要です。

```bash
# 1. キックオフ -> 202 + Content-Location（ステータスURL）
curl -si -H "Prefer: respond-async" http://localhost:3000/\$export
# => HTTP/1.1 202 Accepted
#    Content-Location: http://localhost:3000/$export/status/{id}

# 2. ステータスをポーリング（実行中は202、完了で200 + マニフェスト）
curl -s http://localhost:3000/\$export/status/{id}
# => {"transactionTime":"...","request":"...","requiresAccessToken":false,
#     "output":[{"type":"Patient","url":"http://.../\$export/files/{fileId}","count":2}, ...],"error":[]}

# 3. 出力ファイルをダウンロード（application/fhir+ndjson、1行1リソース）
curl -s http://localhost:3000/\$export/files/{fileId}

# キャンセル（実行中のみ）
curl -si -X DELETE http://localhost:3000/\$export/status/{id}

# コホート単位（以降のポーリング・ダウンロードは上と同じ）
curl -si -H "Prefer: respond-async" http://localhost:3000/Group/{groupId}/\$export
```

対応パラメータ: `_type`（カンマ区切り、`Patient/$export` と `Group/{id}/$export` では未指定でも
Patient は常に含まれる）、
`_since`（ISO 8601、増分エクスポート用）、`_outputFormat`（NDJSON系のみ）。それ以外のパラメータは
デフォルトで 400 エラーになるが、`Prefer: respond-async, handling=lenient` を付けると無視される。

**制限事項**:
- 出力は Postgres に保存(Render無料枠に永続ディスクが無いため)。1ファイルの上限
  `BULK_EXPORT_MAX_FILE_BYTES`(既定10MB、超過時は自動分割)、エクスポート全体の上限
  `BULK_EXPORT_MAX_TOTAL_BYTES`(既定50MB、超過で失敗)。クライアントごと同時1件まで(429)。
- 完了・失敗・キャンセル済みのジョブは `BULK_EXPORT_RETENTION_DAYS`(既定3日)で自動削除される
  (下記「定期メンテナンス」参照)。
- 削除済みリソースはマニフェストの `deleted[]` 配列としては通知されない(出力から単に除外される)。
- ワーカーdynoが無いため、ジョブはWebプロセス内で実行される(ActiveJobの`:async`アダプタ)。
  デプロイ等でプロセスが再起動すると実行中のジョブは失われ、次のポーリングまたは日次cronで
  自動的に `failed` になる(クライアントは再度キックオフすればよい)。
