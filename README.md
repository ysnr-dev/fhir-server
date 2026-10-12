# FHIR Server (JP-Core v1.2.0 / JASPEHR v1.0.0 準拠)

Ruby on Rails (API専用) + PostgreSQL で実装した FHIR サーバーです。
[JP Core Implementation Guide v1.2.0](https://jpfhir.jp/fhir/core/1.2.0/index.html) および
問診票・診療テンプレートについては
[JASPEHR 実装ガイド v1.0.0](https://jaspehr.jp/wp-content/docs/full-ig_v1.0.0/site/index.html)
に準拠した 37 リソース（`Patient` / `Observation` / `MedicationRequest` / `Questionnaire` など）の
CRUD・検索（チェーン検索 / `_has` / `_include` 等）・バージョン管理・条件付き操作・JSON Patch・
オペレーション（`$validate` / `Patient/$everything`）と、`Bundle`（transaction / batch）による
複数リソースの一括処理、SMART Backend Services 認証（任意有効化）を提供します。

## クイックスタート

Docker Desktop を起動した状態で、リポジトリのルートで実行します。

```bash
# ビルド + 起動（初回はイメージビルド、DB作成・マイグレーションを自動実行）
docker compose up --build -d

# 動作確認
curl -s http://localhost:3000/metadata

# テスト
docker compose exec web bash -c "RAILS_ENV=test bin/rails db:prepare && RAILS_ENV=test bundle exec rspec"
```

- `web`（Rails）はホスト `3000` 番、`db`（PostgreSQL 18）はホスト `5433` 番で待ち受けます。
- 既定は認証なし。SMART Backend Services 認証は `FHIR_AUTH_ENABLED=true docker compose up` で有効にします。
- ソースはボリュームマウントされるため再ビルド不要です（`Gemfile` を変更したときだけ `docker compose build`）。
- ローカル（rbenv + Homebrew PostgreSQL）での起動は [docs/setup.md](./docs/setup.md#ローカルでの起動) を参照してください。

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [docs/setup.md](./docs/setup.md) | 動作環境、Docker Compose / ローカルでの起動、テスト、構成メモ、`_sort` の仕様、既知の注意点 |
| [docs/api-guide.md](./docs/api-guide.md) | API クライアント向けの共通仕様（`meta`・ステータスコード）、SMART 認証、管理 API、バリデーション、エラーレスポンス |
| [docs/api-examples.md](./docs/api-examples.md) | 対応リソースとエンドポイント一覧、リソース別の検索・登録例、Bundle、Bulk Data `$export` |
| [docs/operations.md](./docs/operations.md) | 本番デプロイの前提条件と起動、token 検索インデックスの初期化、定期メンテナンス、スモークテスト |
| [docs/DEPLOY_RENDER.md](./docs/DEPLOY_RENDER.md) | Render + Neon での無料ホスティング手順 |
| [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) | fhir-server・fhir-client・MCP サーバーの 4 リポジトリ構成の概観 |
