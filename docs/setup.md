# セットアップ

## 動作環境

- Ruby 4.0.7 / Rails 8.1
- PostgreSQL 18

起動方法は 2 通りあります。用途に応じて選んでください。

- **Docker Compose**（推奨・環境構築不要）: Ruby も PostgreSQL もコンテナで完結
- **ローカル**: rbenv の Ruby + Homebrew の PostgreSQL を直接使用

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
自動で読み込みます。詳細な利用手順は [認証（SMART Backend Services）](./api-guide.md#認証smart-backend-services) を参照してください。

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
- `FHIR_LOCAL_TIMEZONE`（既定 `Asia/Tokyo`）: タイムゾーンを持たない検索値（`date=2026-08-18` など）を
  解釈するゾーン。FHIR の検索仕様は「タイムゾーンが無ければサーバーのタイムゾーン」と定めており、
  UTC で解釈すると JST の朝 9 時前の記録が前日に落ちる。タイムゾーン名か `+09:00` 形式で指定。
  現在の設定は `/metadata` の `implementation.description` に出る
- `SPECIMEN_ACCESSION_SYSTEM`: 設定するとその system の `Specimen.accessionIdentifier` が値なしで
  作成されたとき、サーバーが連番（10 桁 + M10W3 チェックデジット）を採番する

### `_sort` について

- 並べ替えできるのは、抽出列を持つ検索パラメータ（`Fhir::SearchDefinitions` の各定義で
  `column:` を持つもの）と `_id` / `_lastUpdated`。`resource_tokens` 経由でしか引かない
  トークン（`ServiceRequest.category` など）は並べ替えの対象外。
- 対応していないキーは既定（lenient）では黙って無視され、`Prefer: handling=strict` を
  付けると 400 + OperationOutcome でキー名が返る。
- **値を持たない行は方向によらず末尾**（`NULLS LAST`）。Postgres の既定は DESC が
  NULLS FIRST だが、それだと「新しい順」で日付未設定のものが先頭に来てしまうため。
- 同値のタイブレークは `id` 昇順で、ページ送りをまたいでも並びが安定する。
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
