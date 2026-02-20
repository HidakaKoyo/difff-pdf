# ExecPlan: difff-pdf リデザイン + Electron化

## 目的
- 日本語版UIを単一比較導線へ統合し、テキスト/PDFの結果表示を統一する。
- 公開保存機能（save/delete）を廃止する。
- Electron最小シェルを実装し、順調時は未署名 `dmg + zip` を生成する。

## マイルストーン
1. `difff.pl` を単一フォーム + 新UIテンプレート + 自動判定に移行
2. `static/` アセット分離（CSS/JS/icons/fonts）
3. `save.cgi` / `delete.cgi` 完全撤去
4. Electronシェル追加（`electron/main|preload|server`）
5. 配布ビルド（Gate通過時）
6. README / 実装ログ更新

## 受け入れ条件
- 比較ボタンが1つでテキスト/PDFが動作
- PDF2本比較で `srcA/srcB/annA/annB/annComment` が表示
- save/delete導線が存在しない
- `npm run electron:dev` で起動できる
- （Gate通過時）`npm run electron:dist` で `dmg + zip` が生成される

## 進捗
- M1 完了: `difff.pl` を単一フォーム + 自動判定 + 統合結果表示へ移行。
- M2 完了: `static/` を新設（`app.css`, `app.js`, `icons.svg`, `fonts/`）。
- M3 完了: `save.cgi`/`delete.cgi` と `cgi-bin` の対応リンクを削除。
- M4 完了: Electronシェル（`main|server|preload`）と `package.json` を追加。
- M5 完了: `npm run electron:dist` で未署名 `dmg + zip` を生成（強制終了時の子プロセス残留は継続確認）。

## 恒久対策（2026-02-19 追記）

### 目的
- `en` 機能を完全撤去し、Electron起動不安定（`CGI server did not become ready`）を恒久対策で解消する。

### 実施内容
1. `en/` ディレクトリを削除し、`difff.pl` の `EN` リンクを撤去。
2. `electron/server.cjs` で起動判定を二段階化（`/` -> `/cgi-bin/difff.pl` + `compare-form` マーカー）。
3. `DIFFF_DESKTOP_PORT` 競合時の自動ポートフォールバックを追加。
4. `uv sync` にタイムアウト（`DIFFF_DESKTOP_UV_SYNC_TIMEOUT_SEC`）を追加。
5. `startup.log` 常設出力（`BUILD_ID`, roots, port, ready結果, child終了情報）。
6. `package.json` を `0.1.1` へ更新し、build時に `difffBuildSha/difffBuildTime` を埋め込む。
7. READMEに再インストール前チェックと配布物検査手順を追記。

### 受け入れ条件
- `EN` 導線がUIから消え、`/Users/kh/MyWorkspace/difff-pdf/en/` が存在しない。
- 起動時に `startup.log` が生成され、`BUILD_ID` とready診断が記録される。
- `DIFFF_DESKTOP_PORT` 占有時に別ポートへフォールバックして起動継続する。
- ready判定が `compare-form` マーカーを満たすまで待機し、不一致時は明示エラーを返す。

### 追加検証メモ（起動不安定の根因）
- ready待機の内部HTTPクライアントが strict parser で CGI応答を弾き、`Parse Error: Invalid header value char` により `startup.ready` へ到達しない事象を確認。
- 修正: `insecureHTTPParser: true` を適用し、`content-type=text/html` かつ `compare-form` マーカーを満たす場合のみ ready と判定。
- 競合修正: ポート可用性判定の bind を全IFに変更し、IPv6占有時でも `port.fallback` が発動することを確認。
- 補足: macOS runtime も `~/Library/Application Support/difff-pdf/runtime` に寄せ、ログ案内と実配置を一致させた。
