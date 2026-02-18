# ExecPlan: difff PDF比較対応（改訂v4）

## 目的
- テキストモードを変更せず、PDF2本アップロード時に既存split_text準拠で差分を返す。
- annA/annB/annCommentの3成果物を生成し、保存/削除/掃除まで一貫対応する。

## マイルストーン
1. `difff.pl` にPDF分岐とXHTML再構成パイプラインを追加
2. `tools/pdf_annotate_diff.py` でreconstruct/annotate実装
3. `save.cgi`/`delete.cgi` の5PDF運用対応
4. README/ログ整備と検証

## 受け入れ条件
- 既存テキスト比較が動作維持
- PDF比較でHTML差分+annA/annB/annCommentリンクが出る
- 保存でHTML+5PDF、削除で関連全削除
- 上限/依存不足/タイムアウトで明示エラー
- 注釈はベストエフォート（差分HTMLは返す）

## 進捗メモ
- M1 完了: `difff.pl` にPDF分岐と再構成/注釈呼び出しを追加。
- M2 完了: `tools/pdf_annotate_diff.py` のreconstruct/annotateを実装。
- M3 完了: `save.cgi`/`delete.cgi` の5PDF保存削除と保持期間掃除を追加。
- M4 実施: `perl -c` と `uv run --project tools python -m py_compile` を含むuv統一手順で最小動作確認を実施。
