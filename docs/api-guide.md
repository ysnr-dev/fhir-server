# APIクライアントからのアクセス方法

## ベースURL

```
http://localhost:3000
```

## 共通仕様

- リクエスト/レスポンスとも `Content-Type: application/fhir+json` を使用してください
  （サーバーはリクエストボディを raw JSON として解釈するため、`application/json` でも動作します）
- 正常応答のリソースには `meta.versionId` / `meta.lastUpdated` / `meta.profile` が自動付与されます
  （後述の「`meta` の扱い」も参照）
- 正常応答には `ETag: W/"{versionId}"` ヘッダーが付与されます
- 作成成功時は `Location: {baseUrl}/{ResourceType}/{id}/_history/{versionId}` ヘッダーが付与されます
- すべてのエラー応答は `OperationOutcome` リソース（`application/fhir+json`）で返されます

### `meta` の扱い

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

## 認証（SMART Backend Services）

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

## 認証（SMART standalone patient launch）

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

## 管理 API（OAuth クライアントの登録・削除）

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
> 管理 UI を作る場合はサーバー間で中継してください（[fhir-client](../../fhir-client) がその実装です）。
> 管理 API の 401 は `auth-failure-ban`（IP 単位の一時 BAN）には積みません。呼び出し元が単一 IP の
> 中継サーバーになるため、トークンの打ち間違いで FHIR API 全体が遮断されるのを避けています。
> ブルートフォース対策は専用のレート制限 `FHIR_RATE_ADMIN_IP`（既定 30/分）が担います。

## バリデーション（プロファイル検証）

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
   （`Composition` / `Group` / `Task` / `Provenance` / `Appointment` / `Schedule` / `Slot` / `Flag` /
   `CarePlan` / `Goal` / `CareTeam` は JP Core に該当プロファイルが無く基底 HL7 プロファイルのため対象外で、
   手書きバリデータのみが働きます）。
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

## エラーレスポンス例

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
