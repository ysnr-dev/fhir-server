# FHIR Server (JP-Core v1.2.0 準拠)

Ruby on Rails (API専用) + PostgreSQL で実装した FHIR サーバーです。
[JP Core Implementation Guide v1.2.0](https://jpfhir.jp/fhir/core/1.2.0/index.html) に準拠した
`Patient` / `MedicationRequest` / `ServiceRequest` / `Practitioner` / `Organization` リソースの
CRUD・検索・バージョン管理と、`Bundle`（transaction / batch）による複数リソースの一括処理を提供します。

## 動作環境

- Ruby 3.1.0 / Rails 7.0
- PostgreSQL 18

起動方法は 2 通りあります。用途に応じて選んでください。

- **Docker Compose**（推奨・環境構築不要）: Ruby も PostgreSQL もコンテナで完結
- **ローカル**: rbenv の Ruby + Homebrew の PostgreSQL を直接使用

---

## Docker Compose での起動

Docker Desktop（デーモン）が起動していることを確認してください。

```bash
# ビルド + 起動（初回はイメージビルド、DB作成・マイグレーションを自動実行）
docker compose up --build

# バックグラウンド起動する場合
docker compose up --build -d
```

`http://localhost:3000` で待ち受けます。動作確認:

```bash
curl -s http://localhost:3000/metadata
```

### コンテナ内でテスト実行

```bash
docker compose exec web bash -c "RAILS_ENV=test bin/rails db:prepare && RAILS_ENV=test bundle exec rspec"
```

### 停止・後片付け

```bash
docker compose down       # コンテナ停止（DBデータは pg_data ボリュームに残る）
docker compose down -v    # DBデータも含めて削除
```

### 構成メモ

- サービス: `web`（Rails, ホスト `3000` 番）/ `db`（PostgreSQL 18, ホスト `5433` 番 → コンテナ `5432`）
  - ホスト側 `5433` はローカルの Homebrew PostgreSQL(5432) との競合を避けるための割り当て
- DB接続情報は `web` に環境変数で注入（`DATABASE_HOST=db` / `DATABASE_USERNAME=postgres` / `DATABASE_PASSWORD=password`）
- アプリコードはボリュームマウントされるため、ソース変更は再ビルドなしで反映されます
  （`Gemfile` を変更した場合のみ `docker compose build` で再ビルド）

### 動作確認済み環境

- Docker Desktop 4.22.0 / Docker Engine 24.0.5 / Docker Compose v2.20.2
- 本ドキュメントは Compose V2（`docker compose`。ハイフン無し）を前提とします。

### 補足・既知の注意点

- **PostgreSQL 18 のボリューム**: 18 以降の公式イメージはデータを
  `/var/lib/postgresql/{major}` に置くため、ボリュームは `/var/lib/postgresql`（`/data` を付けない）に
  マウントしています。
- **seccomp（古い Docker のみ該当）**: Docker Engine 20.10 系など**古いデーモン**では、既定の
  seccomp プロファイルが Postgres 18 の使う新しいシステムコールをブロックし、`Operation not permitted` で
  起動失敗することがあります。その場合は `docker-compose.yml` の `db` サービスに
  `security_opt: [seccomp:unconfined]` を追加してください。
  **Engine 24.x 以降では不要**（本リポジトリの compose には含めていません）。

---

## ローカルでの起動

### セットアップ

```bash
export PATH="/usr/local/opt/postgresql@18/bin:$PATH"
brew services start postgresql@18   # 未起動の場合

bundle install
bin/rails db:create db:migrate
```

### サーバー起動

```bash
export PATH="/usr/local/opt/postgresql@18/bin:$PATH"
bin/rails s
```

デフォルトで `http://localhost:3000` で待ち受けます。

### テスト実行

```bash
bundle exec rspec
```

> `config/database.yml` の接続情報は環境変数駆動です。環境変数が無ければ従来通り
> ローカルの Unix ソケット + OS ユーザーで接続するため、Docker とローカルのどちらでも同じ設定で動作します。

---

## APIクライアントからのアクセス方法

### ベースURL

```
http://localhost:3000
```

### 共通仕様

- リクエスト/レスポンスとも `Content-Type: application/fhir+json` を使用してください
  （サーバーはリクエストボディを raw JSON として解釈するため、`application/json` でも動作します）
- 正常応答のリソースには `meta.versionId` / `meta.lastUpdated` が自動付与されます
- 正常応答には `ETag: W/"{versionId}"` ヘッダーが付与されます
- 作成成功時は `Location: {baseUrl}/{ResourceType}/{id}/_history/{versionId}` ヘッダーが付与されます
- すべてのエラー応答は `OperationOutcome` リソース（`application/fhir+json`）で返されます

| HTTPステータス | 意味 |
|---|---|
| 200 | 参照・更新・検索成功 |
| 201 | 作成成功 |
| 204 | 削除成功 |
| 400 | JSON不正 / `resourceType` 不一致 |
| 404 | リソースが存在しない |
| 410 | リソースは削除済み（Gone） |
| 412 | `If-Match` のバージョン不一致（楽観的排他制御） |
| 422 | バリデーションエラー（必須項目欠落・値セット不正など） |

### 対応リソース

| リソース | エンドポイント |
|---|---|
| Patient | `/Patient` |
| MedicationRequest | `/MedicationRequest` |
| ServiceRequest | `/ServiceRequest` |
| Practitioner | `/Practitioner` |
| Organization | `/Organization` |

以下、`{Resource}` は上記いずれかに読み替えてください。

| メソッド | パス | 説明 |
|---|---|---|
| `POST` | `/{Resource}` | 作成 |
| `GET` | `/{Resource}/:id` | 参照 |
| `PUT` | `/{Resource}/:id` | 更新（`If-Match` 対応） |
| `DELETE` | `/{Resource}/:id` | 削除（論理削除） |
| `GET` | `/{Resource}/:id/_history` | バージョン履歴（Bundle） |
| `GET` | `/{Resource}/:id/_history/:vid` | 特定バージョンの参照（vread） |
| `GET` | `/{Resource}` | 検索（Bundle） |
| `GET` | `/metadata` | CapabilityStatement |

---

### Patient の例

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

### MedicationRequest の例

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

### ServiceRequest の例

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
```

**必須項目（JP-Core）**: `status`（値セット `draft|active|on-hold|revoked|completed|entered-in-error|unknown`）、
`intent`（値セット `proposal|plan|directive|order|original-order|reflex-order|filler-order|instance-order|option`）、
`subject`。

---

### Practitioner / Organization の例

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

### Bundle（一括処理）の例

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

### エラーレスポンス例

```json
{
  "resourceType": "OperationOutcome",
  "issue": [
    {
      "severity": "error",
      "code": "required",
      "diagnostics": "Patient.identifier is required (JP Core: 1..*)",
      "expression": ["Patient.identifier"]
    }
  ]
}
```
