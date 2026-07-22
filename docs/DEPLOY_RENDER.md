# Render + Neon 無料ホスティング手順(fhir-server / fhir-client)

テスト用途向けに、無料かつ**無料枠の有効期限がない**構成でホスティングする手順。

```
[ブラウザ] ─→ ysnr-fhir-client(Render 静的サイト = frontend/dist)
                │ rewrite /fhir/* /master/*(同一オリジン化)
                ▼
            ysnr-fhir-client-api(Render Web / Rails) ─→ Neon PG #2
                │ HTTPS + Bearer(client_credentials)
                ▼
            ysnr-fhir-server(Render Web / Rails) ─→ Neon PG #1
                ▲ HTTPS + Bearer
[各自ローカルの fhir-mcp-server / fhir-mcp-agent(stdio なのでホスティング不要)]

purge cron: GitHub Actions(このリポジトリの purge_expired.yml)
```

## 採用理由(2026-07 時点)

| サービス | 状況 |
|---|---|
| Render Web サービス | 無料継続(750 時間/月・15 分アイドルでスリープ) |
| Render Postgres | **無料版は 30 日で失効するため使わない** |
| Neon Postgres | 無料・無期限(0.5GB/プロジェクト、アイドル時 scale-to-zero → 復帰約 1 秒) |
| Fly.io / Koyeb / Railway | 無料枠廃止・新規停止・一時クレジットのみ |

制約(許容済み):

- スリープ復帰に約 1 分。フロント → backend → fhir-server と連鎖するため**初回アクセスは最悪 2 分程度**
- 750 時間/月はワークスペース合計。**keep-alive の ping は張らない**(2 サービス常時起動だと超過する)
- Neon は 0.5GB/プロジェクト。テストデータ用途なら十分

## 事前準備

- GitHub に `ysnr-dev/fhir-server` と `ysnr-dev/fhir-client` が push 済みであること
- アカウント作成(いずれもクレカ不要): [Neon](https://neon.tech) / [Render](https://render.com)(GitHub 連携でサインアップ)

## 1. Neon: データベースを 2 つ作る

プロジェクトを 2 つ作成する(プロジェクト単位で無料クォータが付くため分ける):

| プロジェクト | データベース名 | 用途 |
|---|---|---|
| `fhir-server` | `fhir_server_production` | ysnr-fhir-server 用 |
| `fhir-client` | `backend_production` | ysnr-fhir-client-api 用 |

- リージョンは AWS ap-southeast-1(Singapore)推奨(Render の singapore リージョンに合わせる)
- それぞれの **Connection string(pooled)** を控える。形式:
  `postgresql://<user>:<pass>@<endpoint>.neon.tech/<db>?sslmode=require`
- `sslmode=require` が付いていることを確認(Rails は `DATABASE_URL` をそのまま使う。database.yml の変更は不要)

## 2. Render: Blueprint でデプロイ

各リポジトリに `render.yaml` があるので Blueprint として取り込む。

1. Render ダッシュボード → **New → Blueprint** → `ysnr-dev/fhir-server` を選択 → Apply
2. 同様に `ysnr-dev/fhir-client` を選択 → Apply(backend + 静的サイトの 2 サービスが作られる)
3. `sync: false` の環境変数をダッシュボードで設定:

| サービス | 変数 | 値 |
|---|---|---|
| ysnr-fhir-server | `DATABASE_URL` | Neon #1 の接続文字列 |
| | `RAILS_MASTER_KEY` | fhir-server の `config/master.key` の中身 |
| ysnr-fhir-client-api | `DATABASE_URL` | Neon #2 の接続文字列 |
| | `RAILS_MASTER_KEY` | fhir-client/backend の `config/master.key` の中身 |
| | `FHIR_SERVER_CLIENT_ID` / `FHIR_SERVER_CLIENT_SECRET` | 手順 3 で発行後に設定 |

> **ホスト名の注意**: サービス名が既に取られていると Render がサフィックスを付ける
> (例 `ysnr-fhir-server-abcd.onrender.com`)。その場合は
> `FHIR_ALLOWED_HOSTS`(fhir-server)、`FHIR_SERVER_BASE_URL`(client-api)、
> fhir-client/render.yaml の rewrite 先 URL を実ホスト名に合わせて修正すること。

初回デプロイで `bin/rails db:prepare`(entrypoint)がスキーマを流すため、マイグレーション操作は不要。

## 3. SMART クライアント登録(1 回だけ)

fhir-server は認証 ON で公開する。ローカルから Neon #1 に直結してクライアントを発行する:

```bash
cd fhir-server
docker build -t fhir-server .

# fhir-client backend 用(読み取り + 書き込み)
docker run --rm \
  -e RAILS_ENV=production \
  -e DATABASE_URL='postgresql://...neon.tech/fhir_server_production?sslmode=require' \
  -e RAILS_MASTER_KEY=<master.key の中身> \
  -e FHIR_ALLOWED_HOSTS=cli.invalid \
  --entrypoint bin/rails \
  fhir-server 'fhir:register_client[fhir-client-backend,system/*.read system/*.write]'

# MCP 用(読み取りのみの例)
docker run --rm \
  -e RAILS_ENV=production \
  -e DATABASE_URL='postgresql://...neon.tech/fhir_server_production?sslmode=require' \
  -e RAILS_MASTER_KEY=<master.key の中身> \
  -e FHIR_ALLOWED_HOSTS=cli.invalid \
  --entrypoint bin/rails \
  fhir-server 'fhir:register_client[fhir-mcp,system/*.read]'
```

- `client_id` / `client_secret` は**この場でしか表示されない**ので控える
- fhir-client-backend の値を Render の ysnr-fhir-client-api に設定 → 再デプロイ

## 4. purge cron(GitHub Actions)

`ysnr-dev/fhir-server` の **Settings → Secrets and variables → Actions** に登録:

| Secret | 値 |
|---|---|
| `NEON_DATABASE_URL` | Neon #1 の接続文字列 |
| `RAILS_MASTER_KEY` | fhir-server の master.key |

`.github/workflows/purge_expired.yml` が毎日 JST 4:00 に `fhir:purge_expired` を実行する。
初回は **Actions タブ → purge-expired → Run workflow** で手動実行して成功を確認する。

## 5. MCP(ローカル起動)の接続先設定

stdio サーバーなのでホスティング不要。接続先 URL を差し替えるだけ:

```json
{
  "mcpServers": {
    "fhir": {
      "command": "/path/to/fhir-mcp-agent/fhir-mcp-agent",
      "env": {
        "FHIR_BASE_URL": "https://ysnr-fhir-server.onrender.com",
        "FHIR_CLIENT_ID": "<手順3で発行>",
        "FHIR_CLIENT_SECRET": "<手順3で発行>"
      }
    }
  }
}
```

スリープ復帰(約 1 分)中は初回ツール呼び出しがタイムアウトすることがある。
その場合は `curl https://ysnr-fhir-server.onrender.com/up` で起こしてから使う。

## 6. スモークテスト

```bash
BASE=https://ysnr-fhir-server.onrender.com

# ヘルスチェック(スリープ復帰を兼ねる。復帰直後は数十秒かかる)
curl -fsS "$BASE/up"

# トークン取得 → metadata
TOKEN=$(curl -fsS -X POST "$BASE/oauth/token" \
  -d grant_type=client_credentials -d client_id=... -d client_secret=... \
  | jq -r .access_token)
curl -fsS -H "Authorization: Bearer $TOKEN" "$BASE/metadata" | jq .fhirVersion

# フロントエンド(ブラウザで開いて患者検索まで確認)
open https://ysnr-fhir-client.onrender.com
```

- 認証なしで `GET $BASE/Patient` が 401 になることも確認(公開サーバーの保護確認)
- GitHub Actions の purge を手動実行して成功することを確認

## トラブルシューティング

| 症状 | 原因/対処 |
|---|---|
| fhir-server が起動直後にクラッシュ | `FHIR_ALLOWED_HOSTS` 未設定(guardrail)。実ホスト名を設定 |
| `Blocked hosts` エラー | ホスト名サフィックス問題。`FHIR_ALLOWED_HOSTS` を実ホスト名に |
| client-api 経由が 401 のまま | `FHIR_SERVER_CLIENT_ID/SECRET` 未設定 or スコープ不足(書き込みには `system/*.write`) |
| フロントで /fhir が 404 | render.yaml の rewrite 先 URL が実ホスト名とズレている |
| DB 接続エラー | `DATABASE_URL` に `?sslmode=require` が付いているか確認(Neon は TLS 必須) |
| メモリ不足で再起動 | `WEB_CONCURRENCY=1` になっているか確認(無料枠 512MB) |
