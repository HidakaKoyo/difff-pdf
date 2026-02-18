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
- 2026-02-18: annComment描画を右余白180pt集約へ変更（本文は挿入マーク+短線のみ）。フォント自動縮小(9pt→最小6pt)とoverflow時continuationページ追加、summaryにcomment_*指標を追加。
WARN map_a token size mismatch map=6433 seq=6432 token=5khrn4vg7j9c
WARN map_b token size mismatch map=5960 seq=5959 token=5khrn4vg7j9c
Wed Feb 18 19:31:23 2026 PDF annotate summary token=5khrn4vg7j9c skipped_duplicates=1001 map_a_miss=132 map_b_miss=84 comment_pages_extended=6 comment_min_font_used=9.0 comment_continuation_pages=0
WARN map_a token size mismatch map=5186 seq=5185 token=kwxd55hvkvbx
WARN map_b token size mismatch map=5024 seq=5023 token=kwxd55hvkvbx
Wed Feb 18 19:31:44 2026 PDF annotate summary token=kwxd55hvkvbx skipped_duplicates=859 map_a_miss=102 map_b_miss=75 comment_pages_extended=5 comment_min_font_used=9.0 comment_continuation_pages=0
- 2026-02-18: annComment本文マーカーを矢印から番号マークへ変更し、右余白コメントにも同じ番号ラベルを付与。
WARN map_a token size mismatch map=5186 seq=5185 token=vtxprcgp3r9j
WARN map_b token size mismatch map=4750 seq=4749 token=vtxprcgp3r9j
Wed Feb 18 19:35:54 2026 PDF annotate summary token=vtxprcgp3r9j skipped_duplicates=709 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=9.0 comment_continuation_pages=0
- 2026-02-18: annCommentコメント文字を通常ウェイトへ変更（重ね描画を廃止）し、開始フォントサイズを7ptへ調整。折返し計算も通常フォント基準へ統一。
WARN map_a token size mismatch map=5186 seq=5185 token=t3nf6zwf3dfz
WARN map_b token size mismatch map=4750 seq=4749 token=t3nf6zwf3dfz
Wed Feb 18 19:37:49 2026 PDF annotate summary token=t3nf6zwf3dfz skipped_duplicates=709 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0
WARN map_a token size mismatch map=5186 seq=5185 token=wvm6z2qjfe9q
WARN map_b token size mismatch map=4750 seq=4749 token=wvm6z2qjfe9q
Wed Feb 18 19:39:00 2026 PDF annotate summary token=wvm6z2qjfe9q skipped_duplicates=709 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0
- 2026-02-18: annCommentのbboxはみ出し対策として、番号プレフィックス込みで折返し計算し、フォントメトリクスベースの行高へ変更。描画時にコメント枠内クリップを追加し、番号バッジを可変半径化。
WARN map_a token size mismatch map=5186 seq=5185 token=4eyx5zrz6ejf
WARN map_b token size mismatch map=6433 seq=6432 token=4eyx5zrz6ejf
Wed Feb 18 19:42:56 2026 PDF annotate summary token=4eyx5zrz6ejf skipped_duplicates=4475 map_a_miss=36 map_b_miss=72 comment_pages_extended=5 comment_min_font_used=6.0 comment_continuation_pages=3
WARN map_a token size mismatch map=5186 seq=5185 token=sckdei8ude6k
WARN map_b token size mismatch map=4750 seq=4749 token=sckdei8ude6k
Wed Feb 18 19:43:17 2026 PDF annotate summary token=sckdei8ude6k skipped_duplicates=709 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0
- 2026-02-18: annCommentで同一行かつ近接する複数差分コメントを統合する処理を追加（1文字程度の隙間は同一グループ化）。統合コメントは ` / ` 区切りで表示。
WARN map_a token size mismatch map=5186 seq=5185 token=ngermprhqvmp
WARN map_b token size mismatch map=4750 seq=4749 token=ngermprhqvmp
Wed Feb 18 19:48:06 2026 PDF annotate summary token=ngermprhqvmp skipped_duplicates=709 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=15
- 2026-02-18: annCommentの近接差分統合で、コメント文面を ` / ` 連結から「B側トークン連続範囲の再構成」へ変更。差分間の未変更トークン（例: 1文字空き）もコメントへ取り込み、自然な連結文字列で表示するよう修正。
WARN map_a token size mismatch map=5186 seq=5185 token=saiy5xq7yvrj
WARN map_b token size mismatch map=4750 seq=4749 token=saiy5xq7yvrj
Wed Feb 18 19:54:53 2026 PDF annotate summary token=saiy5xq7yvrj skipped_duplicates=709 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=15
