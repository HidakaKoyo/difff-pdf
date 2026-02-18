difff《ﾃﾞｭﾌﾌ》
======================

ウェブベースのテキスト比較ツールです。2つのテキストの差分をハイライト表示します。  
日本語版に加え、英語版も公開されています（英語版URL: https://difff.jp/en/）。

稼働中サービス: https://difff.jp/

![スクリーンショット](http://data.dbcls.jp/~meso/img/difff6.png "difff《ﾃﾞｭﾌﾌ》スクリーンショット")

## まず最初に（最短セットアップ）

`difff.pl` は既存のテキスト比較に加えて、PDF2本アップロード比較（日本語版のみ）をサポートします。  
Python補助処理は **すべて `uv run` 経由** で実行します。

### 前提コマンド

- `perl`（CGI実行用）
- `diff`（既存テキスト差分）
- `pdftotext`（PDFモード必須。`-bbox-layout` を使用）
- `uv`（Python補助処理の実行）

### セットアップ

```bash
cd /path/to/difff-pdf

# Python依存を同期（tools/pyproject.toml + uv.lock）
uv sync --project tools --offline --no-python-downloads || uv sync --project tools
```

オフライン運用時は、事前に必要ホイールをキャッシュしてから `--offline` を使ってください。

### 開発用に起動

```bash
cd /path/to/difff-pdf

# http.server --cgi は /cgi-bin 配下のみ CGI 実行するため、起動前にリンクを作る
mkdir -p cgi-bin
ln -sf ../difff.pl cgi-bin/difff.pl
ln -sf ../index.cgi cgi-bin/index.cgi
ln -sf ../save.cgi cgi-bin/save.cgi
ln -sf ../delete.cgi cgi-bin/delete.cgi

uv run --project tools python -m http.server --cgi 8000
```

ブラウザで以下にアクセスします。

- `http://localhost:8000/cgi-bin/difff.pl`
- または `http://localhost:8000/cgi-bin/index.cgi`

必要に応じて送信先を固定したい場合は、起動前に以下を指定します。

```bash
export DIFFF_BASE_URL='http://localhost:8000/cgi-bin/'
```

## 動作確認手順（立ち上げ確認を兼ねる）

### 1. テキスト比較（既存モード）

1. 画面上部のテキスト入力欄にA/Bを入力する  
2. 「比較」を実行する  
3. 差分ハイライトと文字数カウンタが表示されることを確認する

### 2. PDF比較（GUI）

同じ画面内のPDFフォーム（`pdfA` / `pdfB`）で2本を指定して比較します。  
成功すると、差分HTMLに加えて次のリンクが表示されます。

- `annA.pdf`（A側の削除注釈）
- `annB.pdf`（B側の追加注釈）
- `annComment.pdf`（Aベース: 削除取り消し線 + 追加コメント注釈。右余白にコメント集約）

### 3. CLIスモークテスト（テキスト）

```bash
cd /path/to/difff-pdf
export QUERY_STRING="sequenceA=hogehoge&sequenceB=hagehage"
./index.cgi
```

先頭が `Content-type: text/html; charset=utf-8`、2行目が空行、3行目以降がHTMLなら基本動作OKです。

### 4. Python補助スクリプトの構文確認（uv統一）

```bash
cd /path/to/difff-pdf
uv run --project tools python -m py_compile tools/pdf_annotate_diff.py
```

## PDFモード仕様（日本語版のみ）

- 対象: `/Users/kh/MyWorkspace/difff-pdf/difff.pl`（英語版 `/Users/kh/MyWorkspace/difff-pdf/en/` は非対象）
- 入力: `pdfA` と `pdfB` の両方が指定された場合のみ有効
- 差分計算:
  - `pdftotext -bbox-layout` の **XHTML** を起点に再構成テキストを作成
  - 既存 `split_text` に通して比較（テキストモードと同じ分割規則）
- 注釈成果物:
  - `annotatedA.pdf`
  - `annotatedB.pdf`
  - `annotatedComment.pdf`
- `annotatedComment.pdf` の描画仕様:
  - ページ幅は元PDF + 180pt（右余白追加）
  - 本文には追加箇所の番号マーク + 短いリーダー線のみ描画（本文上の大きなコメント箱は描画しない）
  - コメント本文は右余白に全文表示
  - 同一行で近接する複数コメントは1つに統合し、差分間の未変更トークンも含めて自然な連結文字列として表示
  - フォントは 7pt から自動縮小し、最小 6pt までで収める
  - 6pt でも収まらない場合は continuation ページを追加
- 失敗時方針:
  - bbox対応不能はベストエフォート（差分HTMLは返す）
  - 実行失敗はエラーメッセージを返す

## 環境変数

| 変数名 | 既定値 | 用途 |
|---|---:|---|
| `DIFFF_PDF_MAX_MB` | `50` | PDF1ファイルあたりの上限サイズ（MB） |
| `DIFFF_TEXT_MAX_CHARS` | `5000000` | 抽出後テキスト長の上限 |
| `DIFFF_PDFTOTEXT_CMD` | `/opt/homebrew/bin/pdftotext` | `pdftotext` 実行パス |
| `DIFFF_PDFTOTEXT_TIMEOUT_SEC` | `60` | `pdftotext` 実行タイムアウト秒 |
| `DIFFF_UV_CMD` | `/opt/homebrew/bin/uv` | `uv` 実行パス |
| `DIFFF_UV_TIMEOUT_SEC` | `60` | `uv run` 実行タイムアウト秒 |
| `DIFFF_BASE_URL` | （自動判定） | CGIフォーム送信先のベースURL（末尾 `/` 推奨） |
| `DIFFF_RETENTION_DAYS` | `3` | 公開結果の保持日数 |
| `DIFFF_TMP_TTL_MINUTES` | `120` | `data/tmp` 一時成果物の保持分 |
| `UV_PYTHON` | （任意） | `uv` で使うPythonを固定したい場合に指定 |

## 保存される成果物

PDF比較結果を公開保存すると、HTMLに加えて以下5ファイルを保存します。

- `srcA.pdf`
- `srcB.pdf`
- `annA.pdf`
- `annB.pdf`
- `annComment.pdf`

保存先 `data/` には、Webサーバからの読み書き権限を付与してください。  
保持期間を過ぎた成果物は自動削除されます（`DIFFF_RETENTION_DAYS`）。

## 従来の設置ポイント（CGI）

`difff.pl` はCGIスクリプトです。`index.cgi` から呼び出すか、`difff.pl` を公開対象として配置します。  
主に以下を環境に合わせて調整してください。

```perl
#!/usr/bin/perl
my $url = 'https://example.com/' ;  # 保存結果から再投稿するための送信先
my $diffcmd = '/usr/bin/diff' ;
my $fifodir = '/tmp' ;
```

- `$url` は保存HTMLから再実行する運用が不要なら `./` でも可
- `$fifodir` はWebサーバユーザーがFIFOを作成できるディレクトリを指定

## 背景

作者管理サイト（https://difff.jp/）は無償利用できますが、機密文書を社内サーバで比較したい要望向けにソースが公開されています。  
比較処理は `diff` を使い、比較対象は一時ファイルではなくFIFO（名前付きパイプ）経由で受け渡します。

## 更新履歴

### 2017-08-07

- HTTPSによる暗号化通信に対応

### 2015-06-17

- 結果公開機能を追加

### 2013-03-21

- 文字数カウンタ改良（空白・改行除外の文字数表示）
- 単語数カウント追加

### 2013-03-12

- 入力フォーム直下に比較結果表示する構成に変更
- 入力文書と比較結果を1つのHTMLとして保存・再開可能に
- 文字数カウント機能追加
- 配色を改良（カラー2/モノクロ切替）
- 日本語処理を Perl5.8/UTF-8 に変更

### 2013-01-11

- 英語版を公開

### 2012-10-22

- difff ver.5 のソースをGitHub公開

## License

Copyright &copy; 2004-2025 Yuki Naito
([@meso_cacase](https://twitter.com/meso_cacase))  
This software is distributed under [modified BSD license](https://www.opensource.org/licenses/bsd-license.php).
