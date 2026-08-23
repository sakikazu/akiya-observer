# Akiya Observer

自治体や地域の不動産サイトから空き家・中古住宅情報を収集し、小学校と一緒に地図上で確認するためのRailsアプリケーションです。

## 主な機能

- 物件と小学校の地図表示
- 市区町村、新着物件、掲載終了物件による表示切り替え
- 物件から最寄り小学校までの直線距離表示
- 売買価格・月額賃料の表示
- 番地が公開されていない物件の識別
- ローカル保存画像のギャラリー表示
- ログインユーザーによるお気に入り登録
- 市区町村ごとの週次物件レポート
- 掲載終了・再掲載の記録

## 取得元

現在、以下の公開ページに対応しています。

- 住まいる岡山（OK Smile）
- ココスマ伊那
- 竹田市空き家バンク（＋build.）
- Gaccomの公立小学校情報

取得元ごとに公開項目や取得方法が異なります。例えば、住まいる岡山は一覧ページのみを定期取得するため、座標があっても住所文字列が未登録の物件があります。竹田市空き家バンクは売買・賃貸の詳細と、メイン画像・間取り図を保存します。

## 必要な環境

- Ruby 3.2.6
- Bundler
- Node.js
- Yarn 1.x
- SQLite 3
- curl

Rubyのバージョンは[`.ruby-version`](.ruby-version)を参照してください。

## セットアップ

依存関係のインストール、DB準備などをまとめて実行します。

```bash
bin/setup
```

個別に準備する場合は次のコマンドを実行します。

```bash
bundle install
yarn install
bin/rails db:prepare
```

## 開発サーバー

RailsとJavaScriptのビルド監視を同時に起動します。

```bash
bin/dev
```

既定では`0.0.0.0`へバインドするため、ファイアウォールなどで許可されていれば同一ネットワークの端末からもアクセスできます。ローカル端末だけに限定する場合は次のように起動してください。

```bash
HOST=127.0.0.1 bin/dev
```

Railsだけを起動する場合:

```bash
bin/rails server
```

## テストと静的解析

```bash
bin/rspec
bin/rubocop
bin/brakeman
```

JavaScriptを単独でビルドする場合:

```bash
yarn build
```

## データ取り込み

### 物件

各タスクは対話形式でオプションを指定できます。cronなど非対話環境では既定値が使われます。

```bash
bin/rails crawl:ok_smile
bin/rails crawl:cocosma_ina
bin/rails crawl:taketa_iju
```

環境変数でオプションを明示する例:

```bash
FETCH_DETAIL=true DOWNLOAD_IMAGES=false bin/rails crawl:cocosma_ina
FETCH_DETAIL=true DOWNLOAD_IMAGES=true bin/rails crawl:taketa_iju
```

住まいる岡山とココスマ伊那は、既定では画像をダウンロードしません。竹田市空き家バンクは、既定でメイン画像と間取り図をダウンロードします。

### 小学校

Gaccomの市区町村ページを指定します。誤った自治体への紐付けを避けるため、`MUNICIPALITY_ID`の指定を推奨します。

```bash
bin/rails schools:gaccom_import \
  URL=https://www.gaccom.jp/search/p44/c208_public_es/ \
  MUNICIPALITY_ID=1627
```

### ジオコーディング

住所があり座標がない物件をOpenStreetMap Nominatimで座標化します。取得元を限定する場合は`SOURCE_CODE`を指定します。

```bash
SOURCE_CODE=taketa-iju bin/rails geocode:source_listings
```

### 掲載終了の記録

全件取得の結果を記録してから、当日の掲載物件とDBを照合します。

```bash
DISAPPEAR_CHECK=true bin/rails crawl:taketa_iju
SOURCE_CODE=taketa-iju bin/rails disappear:mark
```

## 定期実行

cron定義は[`config/cron/akiya_observer.cron`](config/cron/akiya_observer.cron)にあります。環境固有の絶対パスを含むため、別環境で使用する場合はパスを変更してください。

```bash
crontab config/cron/akiya_observer.cron
crontab -l
```

## 設定とローカルデータ

次のファイルやディレクトリはGit管理対象外です。

- `.env*`
- `config/master.key`
- SQLite DBを含む`storage/`
- ダウンロードした物件画像
- `.codex`

`config/credentials.yml.enc`を利用する場合は、各環境で`config/master.key`または`RAILS_MASTER_KEY`を安全に管理してください。

## クローリング時の注意

- 取得元の利用規約、robots設定、著作権、データの再利用条件を確認してください。
- 短時間に大量のリクエストを送らず、待機時間を設けてください。
- 取得元の仕様変更により、パーサーが動作しなくなる場合があります。
- 公開されていない住所などを推測して保存しないでください。
- 取得した画像や物件情報を公開・再配布する場合は、取得元の条件を確認してください。

このリポジトリには開発用DBやダウンロード画像は含まれません。
