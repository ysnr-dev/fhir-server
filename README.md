# FHIR Server (JP-Core v1.2.0 / JASPEHR v1.0.0 準拠)

Ruby on Rails (API専用) + PostgreSQL で実装した FHIR サーバーです。
[JP Core Implementation Guide v1.2.0](https://jpfhir.jp/fhir/core/1.2.0/index.html) および
問診票・診療テンプレートについては
[JASPEHR 実装ガイド v1.0.0](https://jaspehr.jp/wp-content/docs/full-ig_v1.0.0/site/index.html)
に準拠した 30 リソース（`Patient` / `Observation` / `MedicationRequest` / `Questionnaire` など）の
CRUD・検索（チェーン検索 / `_has` / `_include` 等）・バージョン管理・条件付き操作・JSON Patch・
オペレーション（`$validate` / `Patient/$everything`）と、`Bundle`（transaction / batch）による
複数リソースの一括処理、SMART Backend Services 認証（任意有効化）を提供します。

## 動作環境

- Ruby 3.4.10 / Rails 8.0
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

### 認証の有効化（任意）

デフォルトでは認証なしで起動します。SMART Backend Services 認証を有効にする場合は、
`FHIR_AUTH_ENABLED` をホスト側で指定して起動します（既定は `false`）。

```bash
# 認証あり
FHIR_AUTH_ENABLED=true docker compose up

# 認証なし（既定）
docker compose up
```

プロジェクトルートに `.env` を置き `FHIR_AUTH_ENABLED=true` と記述しても、Docker Compose が
自動で読み込みます。詳細な利用手順は [認証（SMART Backend Services）](#認証smart-backend-services) を参照してください。

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
- 認証トグル `FHIR_AUTH_ENABLED` も `web` に注入（既定 `false`。ホストの環境変数 / `.env` で上書き可能）
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
- 正常応答のリソースには `meta.versionId` / `meta.lastUpdated` / `meta.profile` が自動付与されます
  （後述の「`meta` の扱い」も参照）
- 正常応答には `ETag: W/"{versionId}"` ヘッダーが付与されます
- 作成成功時は `Location: {baseUrl}/{ResourceType}/{id}/_history/{versionId}` ヘッダーが付与されます
- すべてのエラー応答は `OperationOutcome` リソース（`application/fhir+json`）で返されます

#### `meta` の扱い

`meta` の子要素は「サーバー所有」と「クライアント所有」に分かれます。

| 要素 | 扱い |
|---|---|
| `meta.versionId` / `meta.lastUpdated` | サーバーが採番。書き込み時のクライアント指定値は破棄 |
| `meta.profile` | `Fhir::ResourceRegistry` から導出し、レンダリング時に付与。保存はしない（プロファイル URL の変更が過去バージョンにも即座に反映される） |
| `meta.tag` | **クライアント所有。保存され、read / vread / 検索 / `_history` / Bundle / `$export` のいずれでもそのまま返ります** |
| `meta.security` / `meta.source` | 破棄。アクセス制御に関わるラベルを書き込み側が設定できるべきではないため |

`meta.tag` を保存するのは、FHIR で唯一クライアントが著作するコンテンツとしての meta 子要素であり、
JASPEHR の提出指定（`JSP_QResponse_Submission`）・仮名化指定のようにリソースの一部として意味を持つためです。

```bash
curl -i -X POST http://localhost:3000/Questionnaire \
  -H 'Content-Type: application/fhir+json' \
  -d '{ "resourceType": "Questionnaire", "meta": { "tag": [
          { "system": "http://jaspehr.jp/fhir/CodeSystem/JSP_QResponse_Submission_CS", "code": "submission" }
        ] }, "version": "1.0.0", "name": "ExampleQ", "title": "問診票", "status": "active",
        "subjectType": ["Patient"], "item": [{ "linkId": "q1", "type": "string" }] }'
```

更新（PUT / PATCH）でも `meta.tag` は送られた内容で置き換わります。タグを残したい場合は更新ボディにも
含めてください（送らなければ消えます）。

> `_summary` / `_elements` を使った検索結果には、内容が部分的であることを示す `SUBSETTED` タグが
> レンダリング時に付きます。このタグはサーバー生成のため、その結果をそのまま書き戻しても保存されません。

| HTTPステータス | 意味 |
|---|---|
| 200 | 参照・更新・検索成功 |
| 201 | 作成成功 |
| 204 | 削除成功 |
| 304 | 未変更（条件付き read: `If-None-Match` / `If-Modified-Since`） |
| 400 | JSON不正 / `resourceType` 不一致 |
| 401 | Bearer トークン欠落・無効・期限切れ（認証有効時） |
| 403 | トークンのスコープ不足（認証有効時） |
| 404 | リソースが存在しない |
| 410 | リソースは削除済み（Gone） |
| 412 | `If-Match` のバージョン不一致（楽観的排他制御） |
| 422 | バリデーションエラー（必須項目欠落・値セット不正など） |

### 認証（SMART Backend Services）

デフォルトでは認証なしで動作します。環境変数 `FHIR_AUTH_ENABLED=true` を設定すると、
すべての FHIR エンドポイントで Bearer トークン（OAuth2 client_credentials）が必須になります。
`/metadata`・`/.well-known/smart-configuration`・`/oauth/token` は常に公開です。

```bash
# 1. クライアント登録（client_secret は一度しか表示されません）
bin/rails "fhir:register_client[my-mcp-server,system/*.read]"

# 2. トークン取得
curl -s -X POST http://localhost:3000/oauth/token \
  -d grant_type=client_credentials \
  -d client_id={client_id} -d client_secret={client_secret}

# 3. アクセストークンを付けて API を呼び出し
curl -s http://localhost:3000/Patient -H "Authorization: Bearer {access_token}"
```

スコープは SMART の system 形式（`system/*.read` / `system/Patient.write` / `system/*.*` など）で、
リソース型 × read/write 単位でアクセスを制御します。トークンの有効期限は 1 時間です。

クライアント認証は共有シークレット（client_secret_basic / client_secret_post）に加え、
SMART 標準の **private_key_jwt**（RS384 / ES384 署名の JWT クライアントアサーション）に対応しています。
非対称鍵クライアントは JWKS ファイルを指定して登録します（シークレットは発行されません）:

```bash
bin/rails "fhir:register_client[my-mcp-server,system/*.read,path/to/jwks.json]"

# トークン取得（クライアントは秘密鍵で署名した JWT を提示）
curl -s -X POST http://localhost:3000/oauth/token \
  -d grant_type=client_credentials \
  -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
  -d client_assertion={signed_jwt}
```

アサーションの要件（iss=sub=client_id、aud=トークンエンドポイント URL、exp は 5 分以内、jti 必須）を検証し、
使用済み jti は exp まで記録してリプレイを防止します。

### 認証（SMART standalone patient launch）

患者向けアプリの対話型フロー（authorization_code + PKCE S256 必須）にも対応しています。
ブラウザで `/oauth/authorize` → ログイン → 同意 → 認可コード → トークン交換の順に進み、
発行されたトークンは本人の患者コンパートメント内の読み取りに限定されます
（スコープは `patient/*.read` / `patient/Observation.read` 形式のみ）。

```bash
# クライアント登録（public = シークレットなし、PKCEのみ）
bin/rails "fhir:register_launch_client[my-app,https://app.example/callback,patient/*.read offline_access,public]"

# 患者アカウント登録（既存の Patient に紐付け）
bin/rails "fhir:register_user[patient@example.com,{patient_id},山田太郎]"
```

**リフレッシュトークン**: スコープに `offline_access`（30日）または `online_access`（12時間）を
含めて同意を得ると、トークンレスポンスに `refresh_token` が含まれます。
`grant_type=refresh_token` で新しいアクセストークンを取得でき、リフレッシュトークンは
使用のたびにローテーション（旧トークンは失効し新トークンに置き換え）されます。
使用済みリフレッシュトークンの再提示は漏えいとみなし、同一グラント由来の全トークンを失効させます。

```bash
curl -s -X POST http://localhost:3000/oauth/token \
  -d grant_type=refresh_token \
  -d refresh_token={refresh_token} -d client_id={client_id}
```

`POST /oauth/revoke` にリフレッシュトークンを渡すとグラント全体（アクセストークン含む）が失効します。

**OpenID Connect（ユーザー識別）**: スコープに `openid` を含めて同意を得ると、
トークンレスポンスに `id_token`（RS384 署名の JWT）が含まれます。
`sub`（ログインユーザーの安定 ID）を持ち、`fhirUser` / `profile` スコープを併せて要求すると
`fhirUser` クレーム（`{base_url}/Patient/{id}` の絶対 URL）が付与されます。
認可リクエストで `nonce` を渡すと id_token にそのまま反映されます。
アプリは `GET /.well-known/jwks.json` で公開鍵を取得して署名を検証できます
（discovery の `issuer` / `jwks_uri` / `id_token_signing_alg_values_supported` を参照）。

> **本番運用の注意**: id_token の署名鍵は環境変数 `OIDC_SIGNING_KEY`（RSA 秘密鍵 PEM）で固定してください。
> 未設定だとプロセス起動ごとに一時鍵が生成され、複数インスタンスや再起動をまたいだ id_token の検証が失敗します
> （`openid` を使わない構成では不要）。

### 管理 API（OAuth クライアントの登録・削除）

クライアントの払い出しは上記の rake タスクでも行えますが、UI や運用ツールから扱えるように
HTTP の管理 API も用意しています。**環境変数 `FHIR_ADMIN_TOKEN` を設定したときだけ有効**で、
未設定なら常に `503 admin_api_disabled` を返します（fail closed）。

認証は FHIR のスコープではなく、この専用共有トークン 1 本です。`system/*.*` を持つクライアントが
自分の権限を作り直せてしまうため、あえてスコープ体系から切り離しています。
`FHIR_AUTH_ENABLED` の値には一切依存しません（認証 OFF の開発サーバーでも管理 API は閉じたまま）。

```bash
export ADMIN=$(openssl rand -hex 32)   # 32バイト未満は本番で起動エラーになる

# 一覧（client_secret は絶対に返りません）
curl -s http://localhost:3000/admin/oauth_clients -H "X-FHIR-Admin-Token: $ADMIN"

# バックエンド連携クライアントの登録（client_secret はこのレスポンスにのみ現れます）
curl -s -X POST http://localhost:3000/admin/oauth_clients \
  -H "X-FHIR-Admin-Token: $ADMIN" -H "Content-Type: application/json" \
  -d '{"name":"my-mcp-server","scopes":["system/Patient.read"]}'

# 対話型 launch クライアントの登録（public = シークレットなし、PKCEのみ）
curl -s -X POST http://localhost:3000/admin/oauth_clients \
  -H "X-FHIR-Admin-Token: $ADMIN" -H "Content-Type: application/json" \
  -d '{"name":"my-app","scopes":["patient/*.read","offline_access"],
       "redirect_uris":["https://app.example/callback"],"client_type":"public"}'

# 削除（発行済みトークン・認可コードも同時に消え、消した件数が返ります）
curl -s -X DELETE http://localhost:3000/admin/oauth_clients/{client_id} \
  -H "X-FHIR-Admin-Token: $ADMIN"

# UI 用のスコープ選択肢（対応リソース型と日本語ラベル）
curl -s http://localhost:3000/admin/scopes -H "X-FHIR-Admin-Token: $ADMIN"
```

`Authorization: Bearer {token}` でも同じトークンを渡せます。エラーは FHIR の OperationOutcome ではなく
プレーンな JSON（検証エラーは `{"errors":[...]}` + 422、単一コードは `{"error":...,"error_description":...}`）です。
管理操作は `AuditEvent` に記録されます（`agent.who.display` が `admin-api`、
共有トークンには身元がないため `client_id` は付きません）。

> **注意**: ブラウザから直接叩く想定ではありません。このサーバーは CORS を意図的に無効にしているため、
> 管理 UI を作る場合はサーバー間で中継してください（[fhir-client](../fhir-client) がその実装です）。
> 管理 API の 401 は `auth-failure-ban`（IP 単位の一時 BAN）には積みません。呼び出し元が単一 IP の
> 中継サーバーになるため、トークンの打ち間違いで FHIR API 全体が遮断されるのを避けています。
> ブルートフォース対策は専用のレート制限 `FHIR_RATE_ADMIN_IP`（既定 30/分）が担います。

### 対応リソース

全 30 リソースが同一のエンドポイント群（後述）を持ちます。

| カテゴリ | リソース |
|---|---|
| 基盤 | Patient / Practitioner / PractitionerRole / Organization / Location / Encounter |
| 薬剤 | Medication / MedicationRequest / MedicationDispense / MedicationAdministration / MedicationStatement |
| 検査・レポート | Observation / Specimen / ImagingStudy / DiagnosticReport / ServiceRequest |
| ワークフロー | Task |
| 臨床情報 | Condition / AllergyIntolerance / Procedure / Immunization |
| 保険 | Coverage |
| 問診 | Questionnaire / QuestionnaireResponse |
| 文書 | Composition / DocumentReference / Binary |
| 関係者・機器 | RelatedPerson / Device |
| 集合 | Group |

`Binary` は既定では JSON 表現で返しますが、`Accept: application/pdf` など非 FHIR タイプを指定した
参照ではデコード済みの生コンテンツを元の `contentType` で返します。

正確な一覧と各リソースの検索パラメータは `GET /metadata`（CapabilityStatement）で確認できます。

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
| `DELETE` | `/{Resource}?{criteria}` | 条件付き削除（単一マッチのみ） |
| `GET` | `/{Resource}` | 検索（Bundle）。チェーン検索・`_has`・`_include`/`_revinclude`・`_sort`・`_count`/`_offset`・`_summary`/`_elements`・`_total`・`:missing` 等に対応 |
| `GET` | `/{Resource}/_history` | タイプレベル履歴（`_count` / `_since` 対応） |
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

---

### バリデーション（プロファイル検証）

検証は 2 層構成です。

1. **手書きバリデータ**（`app/services/*_validator.rb`）: 必須項目・値セット・日付書式・参照整合性など、
   リソースごとに要点をチェックします。常に有効で、違反は create/update/patch を 422 で拒否します。
   `Questionnaire` / `QuestionnaireResponse` については、下記のプロファイル検証エンジンが評価できない
   JASPEHR の FHIRPath invariant（`jsp-1`〜`jsp-10` / `jsr-1` / 医療機関番号の書式）もここで実装しています。
2. **プロファイル検証**（`app/lib/fhir/profile/`）: IG の StructureDefinition スナップショットを
   `vendor/<ig>/` に同梱し、それを解釈してカーディナリティ・未知要素・プリミティブ型書式・
   `fixed[x]`/`pattern[x]`・スライシング（`identifier`/`extension` の system/url 判別子）・
   vendor 内で解決できる required バインディングをチェックします。同梱している IG は 2 つです。

   | IG | 同梱先 | 対象リソース |
   |---|---|---|
   | [JP Core v1.2.0](https://jpfhir.jp/fhir/core/1.2.0/index.html) | `vendor/jp_core/` | プロファイルが `http://jpfhir.jp/fhir/core/...` の 25 リソース |
   | [JASPEHR v1.0.0](https://jaspehr.jp/wp-content/docs/full-ig_v1.0.0/site/index.html) | `vendor/jaspehr/` | `Questionnaire` / `QuestionnaireResponse` |

   検証の対象になるかは「そのプロファイル URL が vendor 済みか」だけで決まります
   （`Composition` / `Group` / `Task` は JP Core に該当プロファイルが無く基底 HL7 プロファイルのため
   対象外で、手書きバリデータのみが働きます）。
   `ImagingStudy` は JP Core が Radiology / Endoscopy の 2 プロファイルに分けていますが、レジストリの
   `profile:` は 1 リソース 1 プロファイルなので、汎用側の `JP_ImagingStudy_Radiology` を採用しています
   （2 つは検証の厳密さは同一で、Endoscopy は参照先の型をより狭めるだけです）。
   **非対象**: FHIRPath invariant、外部ターミノロジー（ICD-10 / LOINC 等のコード実在チェック）、
   `targetProfile` に基づく参照先リソースの型検証。

適用モードは `FHIR_PROFILE_VALIDATION` で切り替えます（既定 `warn`）。

| モード | `$validate` | create/update/patch |
|---|---|---|
| `off` | プロファイル検証なし（手書きバリデータのみ） | プロファイル違反はチェックしない |
| `warn`（既定） | プロファイル違反も issue として報告 | ブロックしない。違反は `Rails.logger.info` に記録 |
| `enforce` | プロファイル違反も issue として報告 | 手書きバリデータの違反と合わせて 422 で拒否 |

既存データ・既存クライアントが IG のスライシング/カーディナリティまで厳密に満たしているとは限らないため、
既定は `warn`（可視化のみ）です。`enforce` に切り替える前に、`$validate` や
`bundle exec rspec spec/lib/fhir/profile/payload_helpers_conformance_spec.rb` 相当のチェックで
実データの適合状況を確認してください。

`POST /{Resource}/$validate` はクエリパラメータ `?profile=<URL>` または Parameters リソースの
`profile` パラメータで、レジストリ既定以外のプロファイル URL を指定して検証できます。vendor されていない
URL を指定すると `code: "not-supported"` の issue が返ります（HTTP 200、手書きバリデータの結果は含まれます）。

**同梱データの再生成**: IG のバージョンが上がった場合や `Fhir::ResourceRegistry` にプロファイル URL を
追加/変更した場合は、該当する rake タスクで `vendor/` 以下を再生成してコミットしてください。
ランタイムはコミット済みの同梱データのみを読み、ネットワークアクセスは一切行いません。

```bash
# JP Core: jpfhir.jp は .../core/<version>/package.tgz という URL 規則なのでバージョン指定だけで済む
JP_CORE_PACKAGE_VERSION=1.3.0 bundle exec rake jp_core:vendor

# JASPEHR: 配布パスに URL 規則が無いため URL 側が主。バージョンは _meta のラベルにのみ使われる
JASPEHR_PACKAGE_URL=https://jaspehr.jp/wp-content/docs/full-ig_v1.1.0/site/package.tgz \
  JASPEHR_PACKAGE_VERSION=1.1.0 bundle exec rake jaspehr:vendor
```

どちらも `*_PACKAGE_URL` を指定すればプレリリース版やローカルミラーを読み込めます（指定時はこちらが優先）。
vendor する範囲は各 IG の性質に合わせています。JP Core は自身の canonical 名前空間
（`http://jpfhir.jp/fhir/core/`）に一致するものだけを辿り、JASPEHR は依存する SDC 拡張・JP-CLINS eCS 拡張・
自前の ValueSet/CodeSystem をすべてパッケージに同梱しているため「パッケージが定義している canonical か」で
判定します。

**JASPEHR 対応の既知の制限**:

- `item.type` / `itemControl` / expression language の各 ValueSet は HL7 基底 CodeSystem を include して
  一部を exclude する構成で、その基底 CodeSystem は同梱していません。展開できない値セットは
  「不明」として検査をスキップするため、代わりに手書きバリデータ（`Fhir::Terminology`）が同じ制約を検査します。
- `QuestionnaireResponse.contained` のスライスは判別子が `profile` 型で、本エンジンは `value` 型のみ
  対応するため検査されません（安全側にスキップ）。
- `meta.tag` による検索（`_tag`）は未対応です。値の保存・取得はできます（下記参照）。
- SDC の `$populate` / `$extract` オペレーションは未実装です。

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

### Task の例（ServiceRequest のワークフロー管理）

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

### Questionnaire / QuestionnaireResponse の例（JASPEHR）

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

### Bulk Data $export（一括エクスポート）の例

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

---

## 本番デプロイ

> **無料ホスティング(テスト用途)**: Render + Neon での構成・手順は
> [docs/DEPLOY_RENDER.md](./docs/DEPLOY_RENDER.md) を参照(`render.yaml` /
> `.github/workflows/purge_expired.yml` が対応するリソース定義)。

### 前提条件(満たさないと起動しない)

| 環境変数 | 内容 |
|---|---|
| `RAILS_MASTER_KEY` | credentials 復号キー(`config/master.key` の内容) |
| `FHIR_ALLOWED_HOSTS` | 到達ホスト名(カンマ区切り)。空だと起動エラー |
| `FHIR_AUTH_ENABLED` | 本番はデフォルト `true`。`false` 指定は起動エラー(デモ用途は `FHIR_AUTH_ALLOW_DISABLED=true` で明示的に解除) |

全環境変数の一覧と任意設定(レート制限・IP許可リスト・Sentry等)は
`.env.production.example` を参照。

### 起動

```bash
cp .env.production.example .env.production   # 値を埋める(コミット禁止)
docker compose -f docker-compose.prod.yml up -d
```

- TLS終端は手前のLB/リバースプロキシで行い、**`X-Forwarded-Proto: https` を必ず付与**する
  (無いと force_ssl がリダイレクトループになる)。
- LBのヘルスチェックは `GET /up`(認証・監査・SSL/ホスト検査の対象外)。
- 実患者データの運用ではマネージドPostgreSQL(自動バックアップ・保存時暗号化)を推奨。

#### token検索インデックス(resource_tokens)の初期化

`system|code` に対応した token 検索は `resource_tokens` テーブルを使う。このテーブルは
リソースの書き込み時にしか埋まらないため、**既存データがある環境ではマイグレーション後に
一度だけ**再構築タスクを実行する(新規構築の環境では不要):

```bash
docker compose -f docker-compose.prod.yml exec -T web bin/rails fhir:reindex_tokens
```

### 定期メンテナンス

期限切れトークン/JTIの掃除、および Bulk Data $export のスタックジョブ失敗化・期限切れジョブ削除を
日次cronで実行する(Render+Neon構成では `.github/workflows/purge_expired.yml` がこれを代行する):

```
0 4 * * * docker compose -f /path/to/docker-compose.prod.yml exec -T web bin/rails fhir:purge_expired
0 4 * * * docker compose -f /path/to/docker-compose.prod.yml exec -T web bin/rails fhir:purge_bulk_exports
```

### デプロイ後スモークテスト

```bash
curl -i http://fhir.example.com/metadata        # -> 301 https へ
curl -i https://fhir.example.com/up             # -> 200 {"status":"ok"}
curl -i -H "Host: evil.example" https://fhir.example.com/Patient  # -> 403 Blocked hosts
curl -i https://fhir.example.com/Patient        # -> 401(トークンなし)
# トークン発行 -> API -> 失効 -> 401 の一連:
#   POST /oauth/token (client_credentials) -> GET /Patient (Bearer) -> 200
#   POST /oauth/revoke -> GET /Patient (同じBearer) -> 401
# /oauth/token を11回/分叩く -> 429 + retry-after
```
