# 本番デプロイと運用

> **無料ホスティング(テスト用途)**: Render + Neon での構成・手順は
> [DEPLOY_RENDER.md](./DEPLOY_RENDER.md) を参照(`render.yaml` /
> `.github/workflows/purge_expired.yml` が対応するリソース定義)。

## 前提条件(満たさないと起動しない)

| 環境変数 | 内容 |
|---|---|
| `RAILS_MASTER_KEY` | credentials 復号キー(`config/master.key` の内容) |
| `FHIR_ALLOWED_HOSTS` | 到達ホスト名(カンマ区切り)。空だと起動エラー |
| `FHIR_AUTH_ENABLED` | 本番はデフォルト `true`。`false` 指定は起動エラー(デモ用途は `FHIR_AUTH_ALLOW_DISABLED=true` で明示的に解除) |

全環境変数の一覧と任意設定(レート制限・IP許可リスト・Sentry等)は
`.env.production.example` を参照。

## 起動

```bash
cp .env.production.example .env.production   # 値を埋める(コミット禁止)
docker compose -f docker-compose.prod.yml up -d
```

- TLS終端は手前のLB/リバースプロキシで行い、**`X-Forwarded-Proto: https` を必ず付与**する
  (無いと force_ssl がリダイレクトループになる)。
- LBのヘルスチェックは `GET /up`(認証・監査・SSL/ホスト検査の対象外)。
- 実患者データの運用ではマネージドPostgreSQL(自動バックアップ・保存時暗号化)を推奨。

### token検索インデックス(resource_tokens)の初期化

`system|code` に対応した token 検索は `resource_tokens` テーブルを使う。このテーブルは
リソースの書き込み時にしか埋まらないため、**既存データがある環境ではマイグレーション後に
一度だけ**再構築タスクを実行する(新規構築の環境では不要):

```bash
docker compose -f docker-compose.prod.yml exec -T web bin/rails fhir:reindex_tokens
```

## 定期メンテナンス

期限切れトークン/JTIの掃除、Bulk Data $export のスタックジョブ失敗化・期限切れジョブ削除、
および過ぎた予約枠(Slot)の削除を日次cronで実行する
(Render+Neon構成では `.github/workflows/purge_expired.yml` がこれを代行する):

```
0 4 * * * docker compose -f /path/to/docker-compose.prod.yml exec -T web bin/rails fhir:purge_expired
0 4 * * * docker compose -f /path/to/docker-compose.prod.yml exec -T web bin/rails fhir:purge_bulk_exports
0 4 * * * docker compose -f /path/to/docker-compose.prod.yml exec -T web bin/rails fhir:purge_past_slots
```

`purge_past_slots` は予約枠の掃除。Slot は 15 分刻みなどで機械的に大量生成されるため、
過ぎた枠を残すと件数が積み上がる。保持期間(`SLOT_RETENTION_DAYS`、デフォルト30日)より
前に始まる枠のうち、**予約が押さえていないもの**(`free` / `busy-unavailable` /
`entered-in-error`、および論理削除済み)を履歴ごと物理削除する。`busy` / `busy-tentative` の
枠は残す — 予約の取消・日時変更は枠の現物を読んでから status を戻すため、消すと
それらの操作が 410 で失敗するため。

## デプロイ後スモークテスト

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
