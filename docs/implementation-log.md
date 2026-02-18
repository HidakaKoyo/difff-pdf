# implementation log

- 2026-02-18: PDFモード導入（XHTML再構成 -> Perl split_text -> 注釈3種生成）を開始。
- 2026-02-18: `difff.pl` にPDF専用分岐（multipart+mode=pdf）を追加。
- 2026-02-18: `pdftotext -bbox-layout` + `uv run` パイプラインを実装し、annA/annB/annCommentを生成する経路を追加。
- 2026-02-18: `save.cgi`/`delete.cgi` に5PDF（srcA/srcB/annA/annB/annComment）の保存・削除・期限掃除を追加。
- 2026-02-18: READMEと実行手順を更新し、Python系コマンドは `uv run --project tools` 統一に整理。
- 2026-02-18: READMEを再構成し、uv統一の立ち上げ手順と動作確認手順（テキスト/PDF）を先頭へ整理。
- 2026-02-18: `http.server --cgi` は `/cgi-bin` 配下のみ実行されるため、READMEのローカル起動手順を `cgi-bin` リンク作成 + `/cgi-bin/difff.pl` アクセスへ修正。
- 2026-02-18: `DIFFF_BASE_URL`/自動判定でフォーム送信先URLを解決するよう修正し、ローカル実行時にPDF比較ボタンで `https://difff.jp/` へ遷移しないよう調整。
WARN map_a token size mismatch map=5186 seq=5185 token=uk7i4qvqggr5
WARN map_b token size mismatch map=4750 seq=4749 token=uk7i4qvqggr5
Wed Feb 18 18:47:33 2026 PDF annotate summary token=uk7i4qvqggr5 skipped_duplicates=709 map_a_miss=103 map_b_miss=65
WARN map_a token size mismatch map=5186 seq=5185 token=f5f3dmu446dn
WARN map_b token size mismatch map=4750 seq=4749 token=f5f3dmu446dn
Wed Feb 18 18:49:47 2026 PDF annotate summary token=f5f3dmu446dn skipped_duplicates=709 map_a_miss=103 map_b_miss=65
WARN map_a token size mismatch map=5186 seq=5185 token=znzy7kt8wj2v
WARN map_b token size mismatch map=4750 seq=4749 token=znzy7kt8wj2v
Wed Feb 18 18:49:52 2026 PDF annotate summary token=znzy7kt8wj2v skipped_duplicates=709 map_a_miss=103 map_b_miss=65
WARN map_a token size mismatch map=6433 seq=6432 token=rp9d5tkj2gkk
WARN map_b token size mismatch map=5960 seq=5959 token=rp9d5tkj2gkk
Wed Feb 18 18:50:18 2026 PDF annotate summary token=rp9d5tkj2gkk skipped_duplicates=1001 map_a_miss=132 map_b_miss=84
- 2026-02-18: PDF成果物リンクを `data/...` 相対から `build_data_url()` ベースへ変更し、`/cgi-bin/difff.pl` 実行時の `/cgi-bin/data` 404を解消。
WARN map_a token size mismatch map=6433 seq=6432 token=br92vz4t26jx
WARN map_b token size mismatch map=5960 seq=5959 token=br92vz4t26jx
Wed Feb 18 18:53:00 2026 PDF annotate summary token=br92vz4t26jx skipped_duplicates=1001 map_a_miss=132 map_b_miss=84
