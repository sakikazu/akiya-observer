# リポジトリガイドライン

## プロジェクト構成とモジュール配置
- `app/` に Rails の MVC（controllers/models/views）と assets/JavaScript を配置します。
- `spec/` に RSpec テスト（例: `spec/models`, `spec/factories`）を配置します。
- `config/`、`db/`、`lib/`、`public/` は Rails 標準の構成です。
- フロントエンドは `app/javascript/` から `app/assets/builds/` にビルドします。

## ビルド・テスト・開発コマンド
- `bin/setup` で依存関係のインストールと初期準備を行います。
- `bin/rails server` でローカル起動します。
- `bin/dev` で Rails と JS ビルド監視を同時起動します（`Procfile.dev`）。
- `yarn build` で `esbuild` による JS バンドルを実行します。
- `bin/rspec` でテストを実行します。
- `bin/rubocop` で lint を実行します。
- `bin/brakeman` でセキュリティスキャンを実行します。

## コーディングスタイルと命名規則
- Ruby は `.rubocop.yml` の `rubocop-rails-omakase` を基準とします。
- Ruby/ERB は 2 スペースインデントです。
- クラス/モジュールは CamelCase、ファイルは snake_case を使います。
- JavaScript は `app/javascript/` に置き、esbuild で束ねます。
- クラス/モジュール/主要メソッドには簡潔なコメントを付けます。
- 重要な処理や意図が読み取りづらい箇所には、追加でコメントを付けます。

## テストガイドライン
- テストは RSpec、FactoryBot を使用します（`spec/factories`）。
- スペック名は対象と種別で付けます（例: `spec/models/user_spec.rb`）。
- 変更対象に関連するテストを追加し、`bin/rspec` で実行します。

## コミット・PR ガイドライン
- 既存のコミットは短く要点を示す形式で、日本語の例もあります。
- 簡潔で命令形のメッセージを推奨します（例: "devise 追加", "モデル追加"）。
- PR には変更内容と理由を記載し、可能なら Issue を紐付けます。
- UI 変更はスクリーンショットを添付し、テスト実行状況を明記します。

## 設定と環境
- Ruby は `3.2.6` です（`.ruby-version`）。
- 既定 DB は SQLite です。環境変更時は `config/database.yml` を確認します。
