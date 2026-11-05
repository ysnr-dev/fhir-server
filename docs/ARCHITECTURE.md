# アーキテクチャ概観（6リポジトリ）

JP-Core（問診票は JASPEHR）準拠の FHIR R4 サーバーを中心に、電子カルテの Web クライアント、
院内に常駐する連携エージェント、カルテから起動する SMART アプリ／CDS サービス、
MCP サーバー（TypeScript / Go）が、FHIR REST + SMART の接点だけで結びつく構成です。
リポジトリの間にコード依存はなく、接点はすべて **HTTP と Bearer トークン**です。

| リポジトリ | 役割 | 主なスタック |
|---|---|---|
| `fhir-server` | FHIR R4 サーバー本体（JP-Core IG v1.2.0 / JASPEHR IG v1.0.0 準拠） | Ruby 4.0 / Rails 8（API 専用）/ PostgreSQL 18 |
| `fhir-client` | 電子カルテ UI ＋ プロキシ backend（診療記録・部門オーダー・マスタ・帳票・DICOM・外部連携） | Rails 8（API 専用）/ Vite + React + TypeScript |
| `fhir-client-agent` | 院内常駐エージェント。院内システム（日レセ・SS-MIX2 ストレージ）とカルテの中継 | Go（単一バイナリ） |
| `fhir-smart-app` | カルテから起動する SMART アプリと CDS Hooks サービス（臨床スコア計算） | Vite + React + TypeScript / Node |
| `fhir-mcp-server` | MCP サーバー（stdio ＋ リモート HTTP） | Node.js 20+ / TypeScript / MCP TypeScript SDK |
| `fhir-mcp-agent` | MCP サーバーの Go 移植（stdio 専用） | Go 1.26+ / 公式 MCP Go SDK |

ほかに、実行時の接点を持たない関連リポジトリとして `fhir-ig`（fhir-client の FHIR 出力をまとめた実装ガイド。
FSH + IG Publisher）と `weborca-dev`（日レセの開発用環境。Docker）があります。

診療データの正本は常に `fhir-server` にあります。`fhir-client` が自分の DB に持つのは
**FHIR に置き場の無いもの**（国内マスタ・帳票レイアウト・DICOM の実体・ログイン資格情報・
外部連携の設定と送信待ちなど）だけです。患者・保険・受付はレセコンが正本で、カルテが上流 FHIR へ取り込みます。

---

## 全体構成図

利用者・院内システム → 各リポジトリのアプリケーション → FHIR サーバー → 永続化層、の 4 層。
経路（ブラウザ / 院内エージェント / SMART アプリ・CDS サービス / ローカル MCP / リモート MCP）は
すべて `fhir-server` の FHIR REST に合流します。

```mermaid
flowchart TB
    Browser["ブラウザ<br/>カルテ・部門オーダー・ワークリスト・マスタ・管理画面"]
    Public["患者の端末・待合のモニター<br/>Web 問診・待合表示板（リンクのトークン）"]
    ClaudeLocal["Claude Desktop / Claude Code"]
    ClaudeMobile["Claude スマホアプリ<br/>ローカルプロセスを起動できない"]

    subgraph hospital["院内"]
        ORCA["日レセ（WebORCA）"]
        SSMIX["SS-MIX2 標準化ストレージ<br/>院内の共有フォルダ"]
        AGENTC["fhir-client-agent — Go 常駐<br/>外向きのみ・待ち受けなし"]
    end

    subgraph clientRepo["fhir-client"]
        FE["frontend — React + Vite + TS<br/>:5173"]
        BE["backend — Rails API プロキシ<br/>:3001"]
        BEDB[("PostgreSQL<br/>master_* / 帳票・文書テンプレート / オーダーセット<br/>ログイン / 施設設定 / 外部連携 / SS-MIX2 送信待ち")]
        B2[("Backblaze B2（S3 互換）<br/>DICOM の実体")]
    end

    subgraph smartRepo["fhir-smart-app"]
        SAPP["SMART アプリ — SPA（PKCE）<br/>カルテの iframe で起動"]
        CDS["CDS サービス — CDS Hooks 2.0"]
    end

    subgraph mcpTs["fhir-mcp-server（TypeScript）"]
        MCPSTDIO["dist/index.js — stdio MCP"]
        MCPHTTP["dist/http.js — リモート HTTP MCP<br/>Streamable HTTP /mcp"]
    end

    subgraph mcpGo["fhir-mcp-agent（Go）"]
        AGENT["単一バイナリ — stdio MCP"]
    end

    IDP["外部 IdP（Auth0）"]

    subgraph serverRepo["fhir-server — Rails 8 / JP-Core v1.2.0 + JASPEHR v1.0.0"]
        REST["FHIR REST<br/>38 リソース / 検索 / _history / Bundle / $validate"]
        AUTH["SMART 認可サーバー<br/>token / authorize / introspect / revoke / JWKS"]
        BULK["Bulk Data<br/>$export（system / patient / group）"]
        ADMINAPI["管理 API<br/>oauth_clients / scopes / launch_contexts / delegated_tokens"]
    end

    DB[("PostgreSQL 18<br/>ローカル: Docker :5433 / 本番: Neon")]
    GHA["GitHub Actions<br/>日次 purge cron・CI"]

    Browser -->|HTTPS| FE
    Public -->|HTTPS| FE
    FE -->|"同一オリジン /fhir・/master・/reports・/imaging・/auth・/admin・/integrations ほか"| BE
    BE --- BEDB
    BE --- B2
    ORCA -.->|"PUSH 通知（WebSocket）"| AGENTC
    AGENTC -->|"中立イベント POST / SS-MIX2 メッセージ取得"| BE
    AGENTC -->|"ファイルを書く"| SSMIX
    BE -->|"日レセ API（患者・保険・受付の取り直し、病名・会計の送信）"| ORCA
    Browser -.->|"iframe（EHR launch）"| SAPP
    BE -->|"CDS Hooks（prefetch 同梱）"| CDS
    ClaudeLocal -.->|"stdio（JSON-RPC / MCP）"| MCPSTDIO
    ClaudeLocal -.->|"stdio（JSON-RPC / MCP）"| AGENT
    ClaudeMobile -->|"HTTPS + OAuth"| MCPHTTP
    MCPHTTP -->|"認可を委譲"| IDP

    BE -->|"Bearer"| REST
    SAPP -->|"Bearer（CORS）"| REST
    SAPP -->|"authorize / token（PKCE）"| AUTH
    CDS -.->|"fhirAuthorization の短命トークン（任意）"| REST
    MCPSTDIO -->|"Bearer"| REST
    AGENT -->|"Bearer"| REST
    MCPHTTP -->|"Bearer"| REST
    BE -->|"共有トークンでサーバー間中継"| ADMINAPI
    Browser -.->|"standalone launch（login / consent 画面）"| AUTH

    REST --- DB
    AUTH --- DB
    BULK --- DB
    ADMINAPI --- DB
    GHA -.->|"期限切れトークン / JTI・古い $export・過ぎた Slot を削除"| DB
```

凡例: 実線 = HTTP(S) 呼び出し、点線 = stdio・WebSocket・iframe・外部スケジュール実行、または条件付きの呼び出し。

---

## リポジトリ別の責務

### `fhir-server` — FHIR R4 サーバー本体

ほかのすべてのリポジトリのアップストリーム。接点は HTTP のみ。

| 領域 | 内容 |
|---|---|
| FHIR REST | 38 リソース（`Patient` / `Observation` / `MedicationRequest` / `ServiceRequest` / `Questionnaire` / `CarePlan` / `CareTeam` ほか）の CRUD、チェーン検索・`_has`・`_include` / `_revinclude[:iterate]`、`_history` / vread（条件付きの型レベル `_history` を含む）、条件付き操作、JSON Patch、`$validate`、`Patient/$everything`、Bundle（transaction / batch） |
| 独自オペレーション | `$distinct-dates`（ある日付パラメータが取る値の集合。カルテの日付ナビ用）、`$next-identifier`（患者番号などの連番の払い出し） |
| 認証・認可 | SMART Backend Services（`client_credentials` / client assertion JWT）、SMART v2 スコープ、OpenID Connect（`id_token` / `fhirUser`）、standalone launch、EHR launch（起動文脈・`appContext`・`user/*` スコープ・CORS）、リフレッシュトークン、Token Introspection（RFC 7662）、revoke、JWKS、`.well-known/smart-configuration` |
| Bulk Data | Bulk Data Access IG v2.0.0。`/$export`・`/Patient/$export`・`/Group/{id}/$export` と非同期ジョブ、status / download / cancel |
| 運用・管理 | `/metadata`（CapabilityStatement）、`/up`（ヘルスチェック）、`AuditEvent`（サーバー生成・読み取り専用）、rack-attack のレート制限・一時 ban、Sentry（`SENTRY_DSN` 未設定なら無効）、管理 API（下記） |

管理 API（`/admin/*`、共有トークン `FHIR_ADMIN_TOKEN` で認証）:

| エンドポイント | 用途 |
|---|---|
| `/admin/oauth_clients`・`/admin/scopes` | OAuth クライアントの登録・一覧・削除と、割り当て可能なスコープの一覧 |
| `POST /admin/launch_contexts` | EHR launch の起動文脈（患者・受診・医療者・アプリ・`appContext`）を保存し、5 分・単回の `launch` トークンを返す。医療者の身元はカルテ backend が保証する |
| `POST /admin/delegated_tokens` | CDS Hooks の `fhirAuthorization` に載せる、委任クライアント向けの読み取り専用・短命（5 分）のアクセストークン |

内部構造の要点:

- **永続化**: リソース型ごとに 1 テーブル。本体は `content`（jsonb）にそのまま入れ、検索に使う値だけを
  列へ展開する。`identifier` / token（`system|code`）/ 履歴は `resource_identifiers`・`resource_tokens`・
  `resource_versions` の共有側テーブルへ正規化する。モデル名＝`resourceType` を不変条件にして、
  polymorphic の `resource_type` 列をそのまま FHIR の型として使う
- **宣言的な定義**: `app/lib/fhir/search_definitions/`（検索パラメータ）と `extraction_definitions/`
  （列・token の抽出）にリソース型ごとの定義を置き、`Fhir::ResourceRegistry` が束ねる。
  検索・索引付けのロジックは共通で、型ごとの差分はこの 2 つの定義ファイルだけ
- **ルーティング**: 38 リソースへ同一のルートセットを生成し、すべて `FhirResourcesController` に集約。
  起動時に自動読込を走らせないよう、型のリストは `routes.rb` に文字列で持ち `ResourceRegistry` と手動で同期する
- **プロファイル検証**: `app/lib/fhir/profile/` が IG のパッケージ（`rails jp_core:*` / `jaspehr:*` で取得）を
  読み、`app/services/*_validator.rb` と組み合わせて `$validate` と書き込み時の検証に使う。
  JP-Core にプロファイルの無い型（`Flag` / `CarePlan` / `Goal` / `CareTeam` など）は HL7 の基本定義と手書きのバリデータで扱う
- **検索は既定で lenient**: 未対応の検索パラメータは黙殺する。`Prefer: handling=strict` で 400 にできる
- **本番ガードレール**: 認証の無効化・弱い `FHIR_ADMIN_TOKEN`・`FHIR_ALLOWED_HOSTS` 未設定は
  起動時に例外で落とす（静かに開いたサーバーを作らない）
- 管理 API は FHIR のスコープではなく専用の共有トークン（`FHIR_ADMIN_TOKEN`）で認証し、
  未設定なら常に 503（fail closed）。管理 API の CORS は意図的に無効（FHIR REST の CORS は SMART アプリのために開く）

### `fhir-client` — 電子カルテ UI ＋ プロキシ backend

`fhir-server` の主たる対話型クライアントで、外来・入院の診療業務をひと通り扱います。

- **backend（Rails 8 API 専用, `:3001`）**
  - `/fhir/*` を fhir-server へ中継。**FHIR リソースは自 DB に永続化しない**。書き込みの入口はこの中継 1 本なので、
    SS-MIX2 出力（下記）もここで「書けた transaction」を記録して起こす
  - `/master/*` で国内マスタと施設マスタを自 DB 管理（`master_*` 約 130 テーブル。医薬品 / HOT / 用法、
    検体検査 / 放射線 / 生理 / 内視鏡 / 処置 / 手術 / 輸血 / 食事 / 細菌 / 病理の各オーダーマスタ、
    看護実践用語・病名・CTCAE・BOM・DPC 電子点数表・郵便番号・祝日などの配布マスタ、オーダーセット・化学療法レジメン・
    クリニカルパス定義、薬剤チェック・警告の規則、チャート・ダッシュボード・抽出条件の定義。FHIR ではないプレーンな JSON REST）
  - `/reports/*` で帳票 PDF を生成（ThinReports。処方箋〔院外は JAHIS 規約の QR 付き〕、注射箋・注射ラベル、
    検体・病理・自己血のラベル、検査結果、化学療法の実施計画書・スケジュール表・公開用レジメン、輸血カード、問診票、
    様式テンプレートの文書）と、DPC 様式1 の提出ファイル
  - `/imaging/*` で取り込んだ DICOM を保持・配信。**実体は backend 側（Active Storage → Backblaze B2）**、
    上流には `ImagingStudy` だけを置く
  - `/integrations/*` が外部連携の受け口
    - `receipt/*`: レセコン連携。院内エージェントからの中立イベント（`POST /integrations/receipt/events`、発行済みトークンで認証）を
      受けて日レセ API で患者・保険・受付を取り直し、上流 FHIR の `Patient` / `Coverage` / `Appointment` に揃える。
      病名と診療行為（会計）はカルテから日レセへ送る。日レセの語彙は `Integrations::Orca` の内側で閉じる
    - `ssmix2/*`: SS-MIX2 標準化ストレージ出力。FHIR → HL7 v2.5 の組み立ては backend、ファイル操作は院内エージェントで、
      エージェントが `GET /integrations/ssmix2/messages` で取りに来て `ack` で返す
    - `cds/*`: CDS Hooks（`patient-view` / 処方の `order-select`・`order-sign` / `feedback`）。登録した CDS サービスを
      backend から呼び、prefetch を施設トークンで解決して同梱する
  - `/smart_apps/*` がカルテの「アプリ」タブ向けの一覧と EHR launch の起動（上流 `launch_contexts` へのサーバー間中継）
  - `/intake/*`（Web 問診）と `/waiting_board/*`（待合表示板）は、職員用はログイン、患者・ロビー用は
    発行したリンクのトークン（ヘッダ）で認証する公開の入口を持つ
  - `/auth/*` がアプリ本体のログイン（医療従事者アカウント。上流 `Practitioner` と 1:1 で、
    資格情報だけをローカルに持つ）、`/admin/*` が接続設定・外部システム連携・SMART アプリ / CDS サービスの登録・
    文書テンプレート・各種の独自カテゴリと、上流管理 API へのサーバー間中継、`/facility_settings` が自院と施設ごとの業務設定
  - 上流接続用の `client_secret`、外部システムの受信トークン、CDS サービスの認証トークンは Active Record Encryption で保管
- **frontend（Vite + React + TypeScript, `:5173`）**
  - カルテ（プロブレム・診療記録・処方・注射・検体検査・放射線・生理・内視鏡・処置・手術・麻酔・輸血・病理・
    食事・看護・リハビリ・栄養・他科依頼・指導管理料などのオーダーと結果、化学療法・クリニカルパス、様式文書、
    ファイル、DICOM ビューア、SMART アプリのタブ、CDS カードの吹き出し）、
    各部門のワークリスト、外来 / 入院 / 救急一覧、病棟マップ・ベッド管理、手術カレンダー、予約、
    ホーム・診療ダッシュボード・データ抽出、Web 問診・待合表示板、
    マスタ管理・帳票レイアウト・OAuth クライアント管理・接続設定
  - FHIR R4 の JSON を直接組み立て／解釈（`@types/fhir` の `fhir4` 名前空間）
  - 通知（緊急異常値・オーダー承認待ち・チーム依頼など）は `Task` に統一し、専用のバックエンドを持たず FHIR 検索のポーリングで組み立てる

設計上の要点: 上流の管理 API は CORS 無効のため、ブラウザからは必ず backend 経由になります。

### リポジトリ間の取り決め（FHIR 上の契約）

コード依存が無いぶん、**データの形**が実質的なインターフェースです。形の一覧は `fhir-ig`（実装ガイド）にまとめています。

- **ローカル拡張の名前空間**: `fhir-client` が定義する拡張・CodeSystem・IdSystem は
  `http://fhir-client.local/...` に統一する（`StructureDefinition/order-department`、
  `CodeSystem/medicine-code`、`IdSystem/lab-label-number` など）。
  サーバーは `content` を素通しで保存するので、これらは検証も索引付けもされずに往復する
- **検索したい拡張だけサーバーに登録する**: 上の原則の例外が `Observation` /
  `QuestionnaireResponse` の `problem` などで、プロブレム単位でカルテを縦に読むため、
  ルート直下の拡張を引くローカル検索パラメータをサーバー側に持つ。カルテが新しい検索を必要とするときは
  サーバー側に先に実装し、本番は fhir-server を fhir-client より先にデプロイする
- **サーバー採番**: 患者番号のような連番はクライアントが `$next-identifier` で払い出す。
  検体ラベル番号（`Specimen.accessionIdentifier`）は例外で、値なしの identifier を付けて
  POST するとサーバーが書き込み時に埋める。対象の system は `SPECIMEN_ACCESSION_SYSTEM`
  （両リポジトリで同じ値）で揃える
- **バイナリ**: 患者に紐づく書類は `Binary` + `DocumentReference` を 1 本の transaction Bundle で
  上流へ保存する。一方 DICOM の実体だけは容量の都合で backend 側（B2）に置き、上流には
  `ImagingStudy` のメタデータのみを置く
- **院内システムとの契約は中立イベント**: カルテは連携先の製品もイベント形式も知らない。
  `fhir-client-agent` が連携先の言葉を `patient.changed` / `reception.created` などの中立イベントに直して送り、
  中身はカルテが連携先の API で取り直す

### `fhir-client-agent` — 院内常駐エージェント

院内サーバーで動き続ける Go の単一バイナリ（systemd または Docker Compose）。院内機に Go・Ruby・Docker は要りません。
**外向きの HTTPS + Bearer のみで、待ち受けポートを持ちません**。連携先ごとにアダプタを 1 つ書き、カルテ側は変えません。

| `AGENT_ADAPTER` | 連携先 | 方式 |
|---|---|---|
| `orca-push`（既定） | 日レセ（WebORCA）の PUSH 通知 | WebSocket を購読し、患者情報・受付の通知を中立イベントにしてカルテへ POST |
| `ssmix2-storage` | SS-MIX2 標準化ストレージ（院内の共有フォルダ） | カルテから HL7 v2.5 メッセージを取りに行き、標準化ストレージ・トランザクションストレージの規則でファイルを書く |

`fhir-mcp-agent`（利用者の端末で動く短命の MCP プロセス）とは別物です。

### `fhir-smart-app` — SMART アプリと CDS サービス

eGFR・CHA₂DS₂-VASc・qSOFA などの臨床スコアを計算する。計算式（`packages/scores`）は 2 つの入口で共有します。

| 入口 | 用途 |
|---|---|
| `apps/web`（SMART アプリ） | カルテの「アプリ」タブから EHR launch で iframe 起動。サーバーを持たない public client の SPA（PKCE）で、認可・FHIR API は上流と直接やり取りし、結果を `Observation` として書き戻す |
| `apps/cds`（CDS サービス） | CDS Hooks 2.0 の `patient-view`。カルテ backend から呼ばれ、prefetch の値で同じ計算をして基準を超えたものをカードで返す。カードのリンクは `appContext` で SMART アプリの該当タブを開く |

### `fhir-mcp-server` — MCP サーバー（TypeScript）

| 入口 | 用途 |
|---|---|
| `dist/index.js`（stdio） | Claude Desktop / Claude Code から起動 |
| `dist/http.js`（Streamable HTTP `/mcp`） | スマホ Claude アプリ向けのリモートカスタムコネクタ。`/.well-known/oauth-*` を自動提供し `/mcp` を Bearer で保護 |

リモート版の OAuth は外部 IdP（Auth0）へ委譲し、**接続の入口を守る役割のみ**。
FHIR への接続は固定の SMART Backend Services クレデンシャルを使います。

### `fhir-mcp-agent` — MCP サーバーの Go 移植

- 公式 MCP Go SDK を使った stdio サーバー。**依存は SDK のみ**（HTTP・JSON・テストは標準ライブラリ）
- `internal/server/tools_*.go` にツール、`internal/fhir/` にクライアントとトークン管理、
  `internal/config/` は環境変数と実行バイナリ同居の `.env` を読む
- `make build-darwin-universal` で Intel / Apple Silicon 両対応の単一バイナリを生成。Docker イメージもあり
- 移植から先に進んでおり、TS 版に無い業務寄りのツール（処方・検査結果・transaction）を持つ

### MCP ツール

| ツール | 内容 | TS | Go |
|---|---|:-:|:-:|
| `get_capabilities` | `/metadata` の CapabilityStatement を要約 | ✓ | ✓ |
| `search_fhir` | リソース検索 | ✓ | ✓ |
| `read_fhir` | 単一リソースの取得 | ✓ | ✓ |
| `patient_everything` | `Patient/$everything` | ✓ | ✓ |
| `get_history` | `_history` | ✓ | ✓ |
| `validate_fhir` | `$validate` | ✓ | ✓ |
| `create_fhir` / `update_fhir` / `patch_fhir` | 汎用の書き込み | ✓ | ✓ |
| `post_transaction` | transaction Bundle の投入 | — | ✓ |
| `create_prescription` | 処方（`MedicationRequest`）をまとめて作成 | — | ✓ |
| `create_lab_result` | 検査結果（`Observation` ほか）をまとめて作成 | — | ✓ |

書き込み系は両実装とも `FHIR_MCP_ALLOW_WRITES=true` のときだけ登録します（既定は無効）。

---

## 認証と主要な経路

### machine-to-machine（MCP / fhir-client backend）

```mermaid
sequenceDiagram
    participant C as MCP サーバー / fhir-client backend
    participant A as fhir-server の /oauth/token
    participant F as fhir-server の FHIR REST

    C->>A: client_credentials（または client assertion JWT）
    A-->>C: アクセストークン（system/* スコープ）
    Note over C: トークンをキャッシュし、期限切れで再取得
    C->>F: GET /Patient?... <br/>Authorization: Bearer ...
    F-->>C: Bundle（application/fhir+json）
```

### ユーザー対話（standalone launch）

```mermaid
sequenceDiagram
    participant U as ブラウザ
    participant S as fhir-server
    participant App as クライアントアプリ

    U->>S: GET /oauth/authorize
    S-->>U: ログイン画面 → 同意画面（このアプリ唯一の HTML）
    U->>S: POST /oauth/login → POST /oauth/consent
    S-->>App: 認可コードを付けてリダイレクト
    App->>S: コード交換（POST /oauth/token）
    S-->>App: アクセストークン + id_token（OIDC / fhirUser）
    Note over App,S: 必要に応じて /oauth/introspect・/oauth/revoke
```

### 電子カルテからのアプリ起動（EHR launch）

```mermaid
sequenceDiagram
    participant U as ブラウザ(カルテ)
    participant C as fhir-client backend
    participant S as fhir-server
    participant App as SMART アプリ(iframe)

    U->>C: POST /smart_apps/:id/launch(患者・受診・appContext)
    C->>S: POST /admin/launch_contexts(管理トークン、医療者を名乗る)
    S-->>C: launch トークン(5 分・単回)
    C-->>U: 起動 URL(iss, launch)
    U->>App: iframe で開く
    App->>S: GET /oauth/authorize?launch&aud&scope=launch user/*.read ...
    S-->>App: 画面を出さず 302(認可コード)
    App->>S: POST /oauth/token(PKCE)
    S-->>App: アクセストークン + patient/encounter/appContext + id_token(fhirUser=Practitioner)
    App->>S: GET /Patient/{id} ...(CORS、Bearer)
```

### 判断支援の呼び出し（CDS Hooks）

```mermaid
sequenceDiagram
    participant U as ブラウザ(カルテ)
    participant C as fhir-client backend
    participant S as fhir-server
    participant D as CDS サービス

    U->>C: POST /integrations/cds/patient_view(患者)
    C->>D: GET /cds-services(discovery、5 分キャッシュ)
    C->>S: prefetch テンプレートを施設トークンで解決
    opt 提供元に委任クライアントを紐づけたとき
        C->>S: POST /admin/delegated_tokens
        S-->>C: 読み取り専用・5 分のトークン(fhirAuthorization)
    end
    C->>D: POST /cds-services/{id}(context + prefetch)
    D-->>C: カード
    C-->>U: 正規化したカード(失敗した提供元はカード無し)
    Note over U: 患者帯の「判断支援 N」に表示。リンクは appContext 付きの EHR launch
```

### 院内システムとの連携（fhir-client-agent）

```mermaid
sequenceDiagram
    participant O as 日レセ
    participant G as fhir-client-agent(院内)
    participant C as fhir-client backend
    participant S as fhir-server
    participant F as SS-MIX2 ストレージ(院内)

    O-->>G: PUSH 通知(WebSocket。患者番号と日時だけ)
    G->>C: POST /integrations/receipt/events(中立イベント、発行済みトークン)
    C->>O: 日レセ API で患者・保険・受付を取り直す
    C->>S: Patient / Coverage / Appointment を揃える
    Note over C,S: 画面からの書き込みは /fhir 中継で上流へ。書けた transaction を SS-MIX2 の送信待ちに記録
    G->>C: GET /integrations/ssmix2/messages(ポーリング)
    C-->>G: HL7 v2.5 メッセージ(取りに来た要求の中で組み立て)
    G->>F: 標準化ストレージの規則でファイルを書く
    G->>C: POST /integrations/ssmix2/messages/ack
```

### 2 段構えのログイン（fhir-client）

ブラウザの利用者と、上流に対するクライアント資格情報は別物です。

1. **医療従事者**は fhir-client の `/auth/session` に ID / パスワードでログインする
   （`users` テーブル。上流 `Practitioner` と 1:1、HttpOnly セッション Cookie）
2. **管理者**は `/admin/session` に `ADMIN_TOKEN` をパスフレーズとしてログインする
   （固定ユーザー `administrator`。DB に置かない）
3. 上流への接続は利用者に関係なく、backend が持つ 1 組の SMART Backend Services
   クレデンシャルで行う。上流から見た主体は常に「fhir-client」。
   例外は EHR launch で、起動したアプリのトークンは起動した医療者（`fhirUser`）に紐づく

カルテ以外の入口の認証:

- **院内エージェント**: 管理画面「外部システム連携」で発行した受信トークン（Bearer）
- **Web 問診・待合表示板**: 職員が発行したリンクのトークン（ヘッダ）。出し直すと前のリンクは失効する

### 管理操作（OAuth クライアント管理）

1. ブラウザは fhir-client の `/admin` にパスフレーズでログイン（HttpOnly セッション Cookie）
2. fhir-client backend が上流の共有トークンを付けて中継
3. fhir-server の `/admin/oauth_clients` で登録・一覧・削除
4. 共有トークン未設定なら管理 API は常に **503（fail closed）**

---

## デプロイ構成（Render 無料枠 ＋ Neon）

Render の無料 Postgres は 30 日で失効するため、DB は Neon（無料・無期限）を外部利用します。
手順は [DEPLOY_RENDER.md](DEPLOY_RENDER.md) を参照。

| Render サービス | 種別 | 由来リポジトリ | 役割・備考 |
|---|---|---|---|
| `ysnr-fhir-server` | docker / web | `fhir-server` | FHIR API 本体。`WEB_CONCURRENCY=1`（RAM 512MB）、ヘルスチェック `/up` |
| `ysnr-fhir-client-api` | docker / web | `fhir-client`（backend） | FHIR プロキシ + マスタ / 帳票 / DICOM / 外部連携 API。上流へは登録済みクライアント資格情報で接続 |
| `ysnr-fhir-client` | static | `fhir-client`（frontend） | `/fhir`・`/master`・`/reports`・`/imaging`・`/auth`・`/admin`・`/integrations`・`/intake`・`/waiting_board`・`/smart_apps`・`/facility_settings` などを rewrite で backend に寄せて同一オリジン化（CORS 不要）＋ SPA フォールバック |
| `fhir-smart-app` | static | `fhir-smart-app`（`apps/web`） | SMART アプリ。カルテの iframe に埋め込むため `Content-Security-Policy: frame-ancestors` を出す |
| `fhir-smart-app-cds` | node / web | `fhir-smart-app`（`apps/cds`） | CDS サービス（`node apps/cds/dist/server.js`） |
| `ysnr-fhir-mcp-server` | docker / web | `fhir-mcp-server` | リモート HTTP MCP（`node dist/http.js`）。OAuth は Auth0、ヘルスチェック `/healthz` |
| Neon PostgreSQL | 外部 | 共有（DB は分離） | `fhir-server` と `fhir-client` backend がそれぞれ自分の DB を持つ |
| Backblaze B2 | 外部 | `fhir-client`（backend） | DICOM の実体。Render 無料枠に永続ディスクが無いため外部の S3 互換ストレージを使う |
| （院内） | 常駐 | `fhir-client-agent` | 院内サーバーで systemd / Docker Compose により常駐。外向きの HTTPS のみ |
| （常駐なし） | ローカル | `fhir-mcp-agent` | stdio サーバー。MCP クライアントが必要時にバイナリ / `docker compose run` で起動 |

本番の migration は fhir-server・fhir-client とも Neon の非 pooled URL（`-pooler` 無し）で実行します。

Render 無料枠には cron が無いため、日次のメンテナンスは GitHub Actions
（`.github/workflows/purge_expired.yml`、JST 04:00）から Neon に直結して実行します。

| rake タスク | 消すもの | 保持期間の既定 |
|---|---|---|
| `fhir:purge_expired` | 期限切れのアクセス / リフレッシュトークン、client assertion の JTI | 30 日（`FHIR_TOKEN_RETENTION_DAYS`） |
| `fhir:purge_bulk_exports` | 終了した `$export` と、ハートビートの切れた実行中ジョブ | 3 日（`BULK_EXPORT_RETENTION_DAYS`） |
| `fhir:purge_past_slots` | 過ぎた予約枠（予約が押さえている枠は残す） | 30 日（`SLOT_RETENTION_DAYS`） |

### ローカル開発時のポート

| サービス | ポート | 備考 |
|---|---|---|
| `fhir-server` web | 3000 | |
| `fhir-server` db | 5433 | ホスト側。Homebrew の PostgreSQL(5432) との衝突回避 |
| `fhir-client` backend | 3001 | |
| `fhir-client` frontend | 5173 | Vite dev proxy が `/fhir`・`/master` ほかを backend へ転送 |
| `fhir-client` db | 5434 | 5433 / 5432 との衝突回避 |
| 日レセ（`weborca-dev`） | 8000 | fhir-client の compose profile `orca` でも起動できる |
| `fhir-client-agent` | — | fhir-client の compose profile `agent`（日レセ用と SS-MIX2 用の 2 つ）。待ち受けなし |
| `fhir-smart-app` SMART アプリ | 5180 | ホストの Node で起動（EHR とは別オリジン） |
| `fhir-smart-app` CDS サービス | 5181 | `/cds-services` |

コンテナから fhir-server を参照する場合は `http://host.docker.internal:3000`。
Rails の `HostAuthorization` に阻まれないよう、fhir-client backend は `FHIR_SERVER_HOST_HEADER`
（既定 `localhost:3000`）で上流に許可される `Host` ヘッダーを送出します。
