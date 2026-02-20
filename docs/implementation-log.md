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
- 2026-02-18: PDF赤線（削除側）の近接差分連結を追加。前後 `DIFFF_DIFF_BRIDGE_CHARS`（既定2）で連結判定し、同一ページ・同一line_seqで接続した場合のみ元範囲を外接統合。非連結時は拡張を採用せず元範囲維持。annotate summary に `deleted_ranges_input/output` と `deleted_bridge_merges` を追加。
WARN map_a token size mismatch map=5186 seq=5185 token=cahr5k7t76sr
WARN map_b token size mismatch map=4750 seq=4749 token=cahr5k7t76sr
Wed Feb 18 20:13:57 2026 PDF annotate summary token=cahr5k7t76sr skipped_duplicates=724 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=15 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-18: 赤線過剰描画の原因を調査。`map_a` は1文字トークン化されていたが、描画重複排除を `page+word_seq` で行っていたため、1文字差分でも長い `word` bbox 全体に赤線が伸びるケースを確認。対策として token単位bbox（x方向等分）を `build_token_bbox_map_from_words` で付与し、削除赤線のdedupeキーを `token_index` 優先へ変更。
- 2026-02-18: 実データ検証（token=cahr5k7t76sr）で `input_deleted_tokens=711` に対し従来 `unique_deleted_draw_units=44` だったため、文字差分が word単位に潰れていることを確認。token_bbox + token_index 適用後の試験実行では `unique_deleted_draw_units=608`、`comment_count=20`（従来と同値）を確認。
WARN map_a token size mismatch map=5186 seq=5185 token=eee95c9fimvh
WARN map_b token size mismatch map=4750 seq=4749 token=eee95c9fimvh
Wed Feb 18 20:23:58 2026 PDF annotate summary token=eee95c9fimvh skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=15 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-18: annCommentの文面統合ロジックを赤線統合結果に同期。`build_comment_annotations` で bridged deleted ranges から group lookup を作り、置換コメント（type=c）を同一削除グループ単位で統合するよう変更。これによりコメント中身が現状の赤線まとまりに対応。
- 2026-02-18: コメント統合条件を座標近接だけでなく削除赤線グループID優先に変更。`deleted_group_id` を ops から解決し、同一赤線グループならコメント文面を同一範囲へ再構成して統合。赤線とコメントの対応付けを強化。
WARN map_a token size mismatch map=5186 seq=5185 token=pgvytmnup52y
WARN map_b token size mismatch map=4750 seq=4749 token=pgvytmnup52y
Wed Feb 18 20:35:26 2026 PDF annotate summary token=pgvytmnup52y skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=4 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-18: コメント生成を赤線グループ主軸へ変更。各 bridged deleted range からコメントを1件生成し、対応するB範囲があればその連結文、無ければ赤線A範囲の文（非差分文字を含む）を採用する方式に更新。これにより赤線1つに対してコメント1つを担保。
- 2026-02-18: コメント生成を「赤線グループ1件=コメント1件」に固定。`merge_nearby_comment_annotations` が b範囲未設定コメントを落としていた不具合を修正し、グループ内補完テキスト（A側範囲/近傍）を保持。実データ検証で `deleted_groups=103` と `comment_count=103` を確認。
WARN map_a token size mismatch map=5186 seq=5185 token=qhbemm65tj9f
WARN map_b token size mismatch map=4750 seq=4749 token=qhbemm65tj9f
Wed Feb 18 20:43:24 2026 PDF annotate summary token=qhbemm65tj9f skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
WARN map_a token size mismatch map=5186 seq=5185 token=uk2te772zzvi
WARN map_b token size mismatch map=4750 seq=4749 token=uk2te772zzvi
Wed Feb 18 20:46:48 2026 PDF annotate summary token=uk2te772zzvi skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-18: コメント過剰表示対策。赤線グループでもB側に有意な差分テキストがない場合（削除のみ・空白のみ変更）はコメントを生成しないよう変更。これにより赤線未描画相当に見える箇所へのコメント付与を抑制。
WARN map_a token size mismatch map=4750 seq=4749 token=hwde3xxkpbhs
WARN map_b token size mismatch map=5186 seq=5185 token=hwde3xxkpbhs
Wed Feb 18 20:51:57 2026 PDF annotate summary token=hwde3xxkpbhs skipped_duplicates=548 map_a_miss=66 map_b_miss=105 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=90 deleted_ranges_output=83 deleted_bridge_merges=7
WARN map_a token size mismatch map=4750 seq=4749 token=p26t2vu8pbm4
WARN map_b token size mismatch map=5186 seq=5185 token=p26t2vu8pbm4
Wed Feb 18 20:53:02 2026 PDF annotate summary token=p26t2vu8pbm4 skipped_duplicates=548 map_a_miss=66 map_b_miss=105 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=90 deleted_ranges_output=83 deleted_bridge_merges=7
WARN map_a token size mismatch map=4750 seq=4749 token=r73zyj929yrs
WARN map_b token size mismatch map=5186 seq=5185 token=r73zyj929yrs
Wed Feb 18 20:54:13 2026 PDF annotate summary token=r73zyj929yrs skipped_duplicates=548 map_a_miss=66 map_b_miss=105 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=90 deleted_ranges_output=83 deleted_bridge_merges=7
- 2026-02-18: 追加調整。`map` 欠損で赤線描画できないグループにコメントだけ残るケースを防ぐため、`annotate()` で実際に描画可能な deleted group id 集合を作成し、コメント生成対象をその集合に限定。
WARN map_a token size mismatch map=4750 seq=4749 token=bvn4uzyx7rpp
WARN map_b token size mismatch map=5186 seq=5185 token=bvn4uzyx7rpp
Wed Feb 18 20:55:45 2026 PDF annotate summary token=bvn4uzyx7rpp skipped_duplicates=548 map_a_miss=66 map_b_miss=105 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=90 deleted_ranges_output=83 deleted_bridge_merges=7
WARN map_a token size mismatch map=5186 seq=5185 token=4zvuq56jnrnt
WARN map_b token size mismatch map=4750 seq=4749 token=4zvuq56jnrnt
Wed Feb 18 20:56:13 2026 PDF annotate summary token=4zvuq56jnrnt skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-18: コメント漏れ対策。赤線連動の絞り込みで `type=a`（B側純追加）コメントが落ちていたため、`build_comment_annotations` で純追加コメント経路を復活。削除のみ/空白のみコメント抑制は維持したまま、B側追加差分のコメントを再表示。
WARN map_a token size mismatch map=5186 seq=5185 token=x5k2dr8un5mr
WARN map_b token size mismatch map=4750 seq=4749 token=x5k2dr8un5mr
Wed Feb 18 20:58:38 2026 PDF annotate summary token=x5k2dr8un5mr skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
WARN map_a token size mismatch map=5186 seq=5185 token=w5nse565fhkh
WARN map_b token size mismatch map=4750 seq=4749 token=w5nse565fhkh
Wed Feb 18 21:00:03 2026 PDF annotate summary token=w5nse565fhkh skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-18: コメント番号付与をアンカー共有方式からコメント単位採番へ変更。同一行に複数コメントがある場合もそれぞれ別番号を割り当てるようにした。
WARN map_a token size mismatch map=5186 seq=5185 token=7qbhji435cz8
WARN map_b token size mismatch map=4750 seq=4749 token=7qbhji435cz8
Wed Feb 18 21:03:35 2026 PDF annotate summary token=7qbhji435cz8 skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
WARN map_a token size mismatch map=5186 seq=5185 token=y7gexkythcv3
WARN map_b token size mismatch map=4750 seq=4749 token=y7gexkythcv3
Wed Feb 18 21:05:12 2026 PDF annotate summary token=y7gexkythcv3 skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
WARN map_a token size mismatch map=5186 seq=5185 token=udbcac6n6xjq
WARN map_b token size mismatch map=4750 seq=4749 token=udbcac6n6xjq
Wed Feb 18 21:05:24 2026 PDF annotate summary token=udbcac6n6xjq skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
WARN map_a token size mismatch map=5186 seq=5185 token=ab7dih7pjqg8
WARN map_b token size mismatch map=4750 seq=4749 token=ab7dih7pjqg8
Wed Feb 18 21:05:32 2026 PDF annotate summary token=ab7dih7pjqg8 skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
WARN map_a token size mismatch map=5186 seq=5185 token=u7vtdmdhcbgd
WARN map_b token size mismatch map=4750 seq=4749 token=u7vtdmdhcbgd
Thu Feb 19 00:02:55 2026 PDF annotate summary token=u7vtdmdhcbgd skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
WARN map_a token size mismatch map=5186 seq=5185 token=j8npy4qf9hfb
WARN map_b token size mismatch map=4750 seq=4749 token=j8npy4qf9hfb
Thu Feb 19 00:03:06 2026 PDF annotate summary token=j8npy4qf9hfb skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-19: 本文側の番号マーカーを右方向リーダー線方式から「対象文字の上配置 + 下向きポインタ（三角 + 短いステム）」へ変更。変更文字の上で指し示す方式に統一し、本文の横方向重なりを抑制。
WARN map_a token size mismatch map=5186 seq=5185 token=xq27hhnnwgve
WARN map_b token size mismatch map=4750 seq=4749 token=xq27hhnnwgve
Thu Feb 19 00:06:42 2026 PDF annotate summary token=xq27hhnnwgve skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
WARN map_a token size mismatch map=5186 seq=5185 token=mu9snc9gqdry
WARN map_b token size mismatch map=4750 seq=4749 token=mu9snc9gqdry
Thu Feb 19 00:07:52 2026 PDF annotate summary token=mu9snc9gqdry skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-19: 本文側番号マーカーの下向きポインタを微調整（tip/stemを下方向へ約0.45pt相当）し、直前要望に合わせて指し位置をわずかに下げた。
WARN map_a token size mismatch map=5186 seq=5185 token=samjrwag8py6
WARN map_b token size mismatch map=4750 seq=4749 token=samjrwag8py6
Thu Feb 19 00:09:10 2026 PDF annotate summary token=samjrwag8py6 skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
WARN map_a token size mismatch map=5186 seq=5185 token=xb7a8s2kbdkq
WARN map_b token size mismatch map=4750 seq=4749 token=xb7a8s2kbdkq
Thu Feb 19 00:10:30 2026 PDF annotate summary token=xb7a8s2kbdkq skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
WARN map_a token size mismatch map=5186 seq=5185 token=hjvcqithqbav
WARN map_b token size mismatch map=4750 seq=4749 token=hjvcqithqbav
Thu Feb 19 00:11:33 2026 PDF annotate summary token=hjvcqithqbav skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-19: 本文側番号マーカーをさらに下方向へ微調整し、矢印ステム線を廃止。三角ポインタ先端のみで変更点を示す描画に変更。
WARN map_a token size mismatch map=5186 seq=5185 token=2xjk59kmfp48
WARN map_b token size mismatch map=4750 seq=4749 token=2xjk59kmfp48
Thu Feb 19 00:13:34 2026 PDF annotate summary token=2xjk59kmfp48 skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-19: 番号バッジ半径を固定（1桁基準）し、2桁時はバッジ内フォントのみ縮小する方式へ変更。あわせてバッジ/三角ポインタをさらに下方向へ微調整。
WARN map_a token size mismatch map=5186 seq=5185 token=w4m8eeajep7f
WARN map_b token size mismatch map=4750 seq=4749 token=w4m8eeajep7f
Thu Feb 19 00:15:55 2026 PDF annotate summary token=w4m8eeajep7f skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-19: 番号フォント縮小ロジックを撤廃し、バッジ半径のみ縮小（r=2.9）へ変更。フォントサイズは固定で描画。
WARN map_a token size mismatch map=5186 seq=5185 token=53egwveduj3m
WARN map_b token size mismatch map=4750 seq=4749 token=53egwveduj3m
Thu Feb 19 00:17:42 2026 PDF annotate summary token=53egwveduj3m skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-19: バッジ内番号フォントを全体で +1pt（4.7pt -> 5.7pt）に調整。
WARN map_a token size mismatch map=5186 seq=5185 token=r89tphybsam6
WARN map_b token size mismatch map=4750 seq=4749 token=r89tphybsam6
Thu Feb 19 00:19:03 2026 PDF annotate summary token=r89tphybsam6 skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-19: 日本語版UIを単一フォーム化。`sequenceA/sequenceB/pdfA/pdfB` を1フォームで送信し、PDF2本がある場合はPDF比較優先とする判定へ変更。
- 2026-02-19: `difff.pl` のインラインCSS/JSを撤去し、`static/app.css` `static/app.js` `static/icons.svg` へ分離。アイコン中心の結果/入力UIへ刷新。
- 2026-02-19: 公開機能を廃止。`save.cgi` `delete.cgi` と `cgi-bin` の対応リンクを削除。
- 2026-02-19: Electron最小シェルを追加（`electron/main.cjs` `electron/server.cjs` `electron/preload.cjs`）。`npm run electron:dev` と `electron:dist` の実行口を追加。
WARN map_a token size mismatch map=5186 seq=5185 token=kdtvw3iingns
WARN map_b token size mismatch map=4750 seq=4749 token=kdtvw3iingns
Thu Feb 19 00:51:14 2026 PDF annotate summary token=kdtvw3iingns skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-19: `npm run electron:dist` を実行し、`dist/difff-pdf-0.1.0-arm64.dmg` と `dist/difff-pdf-0.1.0-arm64-mac.zip` の未署名配布物を生成。
- 2026-02-19: 強制終了時にローカルCGI子プロセスが残るケースを確認。`main.cjs` に `SIGINT/SIGTERM` の明示クリーンアップ経路を追加（GUI終了操作での最終確認は継続）。
WARN map_a token size mismatch map=5186 seq=5185 token=6ktpydkhugjw
WARN map_b token size mismatch map=4750 seq=4749 token=6ktpydkhugjw
Thu Feb 19 00:56:39 2026 PDF annotate summary token=6ktpydkhugjw skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-19: DMG起動時の `No such CGI script ('/cgi-bin/difff.pl')` 対策。Electron起動時に `app.asar.unpacked` をソースとして一時ランタイムディレクトリ（`difff-pdf-runtime-*`）を生成し、`cgi-bin` と必要資産を組み立ててから `http.server --cgi` を起動する方式へ変更。
- 2026-02-19: DMG起動時の `tools/.venv` 依存崩れ（`libpython3.12.dylib` 不足）対策として、Electron起動前にランタイム側で `UV_PROJECT_ENVIRONMENT` を固定し `uv sync`（offline優先・失敗時通常sync）で実行環境を再構築する方式へ変更。パッケージには `tools/.venv` を同梱しない設定に更新。
- 2026-02-19: 起動待機ロジックを改善。Ready判定を `/cgi-bin/difff.pl` からサーバルート `/` へ変更し、HTTP応答が返ることを起動条件化。`DIFFF_DESKTOP_STARTUP_TIMEOUT_SEC`（既定120秒）を導入し、遅い環境でもタイムアウトしにくくした。stderr詳細をタイムアウトエラーに含めるよう更新。
- 2026-02-19: 恒久対策として `en/` ディレクトリを廃止し、`difff.pl` の `EN` 導線を削除。日本語版のみ提供へ統一。
- 2026-02-19: `electron/server.cjs` を更新し、ready判定を二段階化（`/` 応答確認 + `/cgi-bin/difff.pl` で `id='compare-form'` マーカー検証）。判定失敗時にHTTP要約とstderrをエラーへ付与。
- 2026-02-19: `DIFFF_DESKTOP_PORT` の競合時に空きポートへ自動フォールバックする処理を追加。`DIFFF_DESKTOP_READY_TIMEOUT_SEC`（互換で `DIFFF_DESKTOP_STARTUP_TIMEOUT_SEC` も受理）を導入。
- 2026-02-19: 起動時 `uv sync` にタイムアウト（`DIFFF_DESKTOP_UV_SYNC_TIMEOUT_SEC`, default 180s）を導入し、timeout/失敗時のstdout+stderrを起動エラーへ反映。
- 2026-02-19: 起動診断ログを `~/Library/Application Support/difff-pdf/logs/startup.log` に常設。`BUILD_ID`, source/runtime root, port, ready結果, child exit を記録。
- 2026-02-19: `package.json` を `0.1.1` へ更新。`electron:dev`/`electron:dist` で `BUILD_ID` 構成要素（sha/time）を埋め込む運用へ変更。
- 2026-02-19: `README.md` を再構成し、再インストール前チェック、配布物検査、起動失敗時のログ確認手順を追記。
- 2026-02-19: 追加調査で root cause を特定。ready判定用 `http.request` が CGIレスポンスを strict parser で処理し `Parse Error: Invalid header value char` になっていたため、`insecureHTTPParser: true` を適用して待機判定を通るよう修正。
- 2026-02-19: ポート競合判定の bind チェックが `127.0.0.1` 限定だったため、IPv6/全IF占有ケースで誤判定していた。bindチェックを全IFへ変更し、`port.fallback` が確実に発火するよう修正。
- 2026-02-19: ready判定に `content-type: text/html` 条件を追加。静的 `difff.pl` ソース配信（text/plain）を誤って「ready」と判定するケースを防止。
- 2026-02-19: macOS の runtime 配置を `~/Library/Application Support/difff-pdf/runtime` に統一し、`startup.log` の案内と実挙動を一致させた。
WARN map_a token size mismatch map=5186 seq=5185 token=jgi9wm5my3vd
WARN map_b token size mismatch map=4750 seq=4749 token=jgi9wm5my3vd
Fri Feb 20 10:18:45 2026 PDF annotate summary token=jgi9wm5my3vd skipped_duplicates=160 map_a_miss=103 map_b_miss=65 comment_pages_extended=5 comment_min_font_used=7.0 comment_continuation_pages=0 comment_merged_groups=0 deleted_ranges_input=111 deleted_ranges_output=103 deleted_bridge_merges=8
- 2026-02-19: 結果UIを調整。ハイライト配色切替（緑/モノクロ）を撤去して青表示固定に変更。PDF成果物リンクは下部セクションから結果ヘッダー（全画面ボタンと同列）へ移動し、タイトル表記を `pdf` に統一。
- 2026-02-20: READMEに `example.png`（`annComment.pdf` 出力例）を追加。
- 2026-02-20: テスト用PDFを `public/A-base.pdf` / `public/B-mod.pdf` へ差し替え（旧 `public/テスト用_変更前A.pdf` / `public/テスト用_変更後B.pdf` を廃止）。
