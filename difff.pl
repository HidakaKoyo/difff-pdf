#!/usr/bin/perl

# テキスト比較ツール difff《ﾃﾞｭﾌﾌ》： 2つのテキストの差分をハイライト表示するCGI
#
# 比較するテキストとして、HTTPリクエストから sequenceA および sequenceB を取得し、
# diffコマンドを用いて文字ごと（英単語は単語ごと）に比較し差分をハイライト表示する
#
# 2012-10-22 Yuki Naito (@meso_cacase)
# 2013-03-07 Yuki Naito (@meso_cacase) 日本語処理をPerl5.8/UTF-8に変更
# 2013-03-12 Yuki Naito (@meso_cacase) ver.6 トップページを本CGIと統合
# 2015-06-17 Yuki Naito (@meso_cacase) ver.6.1 結果を公開する機能を追加

use warnings ;
use strict ;
use utf8 ;
use POSIX ;
use CGI ;
use JSON::PP ;
use File::Path qw(make_path remove_tree) ;
use Time::HiRes qw(time) ;

# フォーム送信先URL。DIFFF_BASE_URLがあればそれを優先し、なければ実行環境から自動判定する
my $url = resolve_base_url() ;

my $diffcmd = '/usr/bin/diff' ;  # diffコマンドのパスを指定
my $fifodir = '/tmp' ;           # FIFOを作成するディレクトリを指定
my $datadir = 'data' ;
my $tmpdir  = "$datadir/tmp" ;

my $pdf_max_mb                = get_env_int('DIFFF_PDF_MAX_MB', 50) ;
my $text_max_chars            = get_env_int('DIFFF_TEXT_MAX_CHARS', 5000000) ;
my $retention_days            = get_env_int('DIFFF_RETENTION_DAYS', 3) ;
my $tmp_ttl_minutes           = get_env_int('DIFFF_TMP_TTL_MINUTES', 120) ;
my $pdftotext_timeout_sec     = get_env_int('DIFFF_PDFTOTEXT_TIMEOUT_SEC', 60) ;
my $uv_timeout_sec            = get_env_int('DIFFF_UV_TIMEOUT_SEC', 60) ;
my $pdftotext_cmd             = $ENV{'DIFFF_PDFTOTEXT_CMD'} // '/opt/homebrew/bin/pdftotext' ;
my $uv_cmd                    = $ENV{'DIFFF_UV_CMD'} // '/opt/homebrew/bin/uv' ;
my $data_url                  = build_data_url($url) ;

binmode STDOUT, ':utf8' ;        # 標準出力をUTF-8エンコード
binmode STDERR, ':utf8' ;        # 標準エラー出力をUTF-8エンコード

# PDFアップロード比較モード（multipart/form-data + mode=pdf）
if (is_pdf_request()){
	process_pdf_request() ;
	exit ;
}

# ▼ HTTPリクエストからクエリを取得し整形してFIFOに送る
my %query = get_query_parameters() ;

my $sequenceA = $query{'sequenceA'} // '' ;
utf8::decode($sequenceA) ;  # utf8フラグを有効にする

my $sequenceB = $query{'sequenceB'} // '' ;
utf8::decode($sequenceB) ;  # utf8フラグを有効にする

# 両方とも空欄のときはトップページを表示
$sequenceA eq '' and $sequenceB eq '' and print_html() ;

my $fifopath_a = "$fifodir/difff.$$.A" ;  # $$はプロセスID
my @a_split = split_text( escape_char($sequenceA) ) ;
my $a_split = join("\n", @a_split) . "\n" ;
fifo_send($a_split, $fifopath_a) ;

my $fifopath_b = "$fifodir/difff.$$.B" ;  # $$はプロセスID
my @b_split = split_text( escape_char($sequenceB) ) ;
my $b_split = join("\n", @b_split) . "\n" ;
fifo_send($b_split, $fifopath_b) ;
# ▲ HTTPリクエストからクエリを取得し整形してFIFOに送る

# ▼ diffコマンドの実行
(-e $diffcmd) or print_html("ERROR : $diffcmd : not found") ;
(-x $diffcmd) or print_html("ERROR : $diffcmd : not executable") ;
my @diffout = `$diffcmd -d $fifopath_a $fifopath_b` ;
my @diffsummary = grep /(^[^<>-]|<\$>)/, @diffout ;
# ▲ diffコマンドの実行

# ▼ 差分の検出とHTMLタグの埋め込み
my ($a_start, $a_end, $b_start, $b_end) = (0, 0, 0, 0) ;
foreach (@diffsummary){  # 異なる部分をハイライト表示
	if ($_ =~ /^((\d+),)?(\d+)c(\d+)(,(\d+))?$/){       # 置換している場合
		$a_end   = $3 || 0 ;
		$a_start = $2 || $a_end ;
		$b_start = $4 || 0 ;
		$b_end   = $6 || $b_start ;
		$a_split[$a_start - 1] = '<em>' . ($a_split[$a_start - 1] // '') ;
		$a_split[$a_end - 1]  .= '</em>' ;
		$b_split[$b_start - 1] = '<em>' . ($b_split[$b_start - 1] // '') ;
		$b_split[$b_end - 1]  .= '</em>' ;
	} elsif ($_ =~ /^((\d+),)?(\d+)d(\d+)(,(\d+))?$/){  # 欠失している場合
		$a_end   = $3 || 0 ;
		$a_start = $2 || $a_end ;
		$b_start = $4 || 0 ;
		$b_end   = $6 || $b_start ;
		$a_split[$a_start - 1] = '<em>' . ($a_split[$a_start - 1] // '') ;
		$a_split[$a_end - 1]  .= '</em>' ;
	} elsif ($_ =~ /^((\d+),)?(\d+)a(\d+)(,(\d+))?$/){  # 挿入している場合
		$a_end   = $3 || 0 ;
		$a_start = $2 || $a_end ;
		$b_start = $4 || 0 ;
		$b_end   = $6 || $b_start ;
		$b_split[$b_start - 1] = '<em>' . ($b_split[$b_start - 1] // '') ;
		$b_split[$b_end - 1]  .= '</em>' ;
	} elsif ($_ =~ /> <\$>/){  # 改行の数をあわせる処理
		my $i = ($a_start > 1) ? $a_start - 2 : 0 ;
		while ($i < @a_split and not $a_split[$i] =~ s/<\$>/<\$><\$>/){ $i ++ }
	} elsif ($_ =~ /< <\$>/){  # 改行の数をあわせる処理
		my $i = ($b_start > 1) ? $b_start - 2 : 0 ;
		while ($i < @b_split and not $b_split[$i] =~ s/<\$>/<\$><\$>/){ $i ++ }
	}
}
# ▲ 差分の検出とHTMLタグの埋め込み

# ▼ 比較結果のブロックを生成してHTMLを出力
my $a_final = join '', @a_split ;
my $b_final = join '', @b_split ;

# 変更箇所が<td>をまたぐ場合の処理、該当箇所がなくなるまで繰り返し適用
while ( $a_final =~ s{(<em>[^<>]*)<\$>(([^<>]|<\$>)*</em>)}{$1</em><\$><em>$2}g ){}
while ( $b_final =~ s{(<em>[^<>]*)<\$>(([^<>]|<\$>)*</em>)}{$1</em><\$><em>$2}g ){}

my @a_final = split /<\$>/, $a_final ;
my @b_final = split /<\$>/, $b_final ;

my $par = (@a_final > @b_final) ? @a_final : @b_final ;

my $table = '' ;
foreach (0..$par-1){
	defined $a_final[$_] or $a_final[$_] = '' ;
	defined $b_final[$_] or $b_final[$_] = '' ;
	$a_final[$_] =~ s{(\ +</em>)}{escape_space($1)}ge ;
	$b_final[$_] =~ s{(\ +</em>)}{escape_space($1)}ge ;
	$table .=
"<tr>
	<td>$a_final[$_]</td>
	<td>$b_final[$_]</td>
</tr>
" ;
}

#- ▽ 文字数をカウントしてtableに付加
my ($count1_A, $count2_A, $count3_A, $wcount_A) = count_char($sequenceA) ;
my ($count1_B, $count2_B, $count3_B, $wcount_B) = count_char($sequenceB) ;

$table .= <<"--EOS--" ;
<tr>
	<td><font color=gray>
		文字数: $count1_A<br>
		空白数: @{[$count2_A - $count1_A]} 空白込み文字数: $count2_A<br>
		改行数: @{[$count3_A - $count2_A]} 改行込み文字数: $count3_A<br>
		単語数: $wcount_A
	</font></td>
	<td><font color=gray>
		文字数: $count1_B<br>
		空白数: @{[$count2_B - $count1_B]} 空白込み文字数: $count2_B<br>
		改行数: @{[$count3_B - $count2_B]} 改行込み文字数: $count3_B<br>
		単語数: $wcount_B
	</font></td>
</tr>
--EOS--
#- △ 文字数をカウントしてtableに付加

my $message = <<"--EOS--" ;
<div id=result>
<table cellspacing=0>
$table</table>

<p>
	<input type=button id=hide value='結果のみ表示 (印刷用)' onclick='hideForm()'> |
	<input type=radio name=color value=1 onclick='setColor1()' checked>
		<span class=blue >カラー1</span>
	<input type=radio name=color value=2 onclick='setColor2()'>
		<span class=green>カラー2</span>
	<input type=radio name=color value=3 onclick='setColor3()'>
		<span class=black>モノクロ</span>
</p>
</div>

<div id=save>
<hr><!-- ________________________________________ -->

<h4>この結果を公開する</h4>

<form method=POST id=save name=save action='${url}save.cgi'>
<p>この結果をﾃﾞｭﾌﾌサーバに保存し、公開用のURLを発行します。<br>
削除パスワードを設定しておけば、あとで消すこともできます。<br>
<b>公開期間は${retention_days}日間です。</b>公開期間を過ぎると自動的に削除されます。</p>

<table id=passwd>
<tr>
	<td class=n>削除バスワード：<input type=text name=passwd size=10 value=''></td>
	<td class=n>設定したパスワードは後で確認することが<br>できませんので必ず控えてください。</td>
</tr>
</table>

<input type=submit onclick='return savehtml();' value='結果を公開する'>

<p>「結果を公開する」を押さない限り、入力した文書などがサーバに保存されることはありません。<br>
この機能はテスト運用中のものです。予告なく提供を中止することがあります。</p>
</form>
</div>
--EOS--

print_html($message) ;
# ▲ 比較結果のブロックを生成してHTMLを出力

exit ;

# ====================
sub is_pdf_request {
	return 0 unless defined $ENV{'CONTENT_TYPE'} ;
	return ($ENV{'CONTENT_TYPE'} =~ m{multipart/form-data}i) ? 1 : 0 ;
} ;
# ====================
sub process_pdf_request {
	cleanup_tmp_artifacts() ;

	my $cgi = CGI->new ;
	(($cgi->param('mode') // '') eq 'pdf')
		or print_html('ERROR : invalid pdf mode') ;

	my $upload_a = $cgi->upload('pdfA') ;
	my $upload_b = $cgi->upload('pdfB') ;
	(($upload_a and $upload_b) or (not $upload_a and not $upload_b))
		or print_html('ERROR : 2つのPDFを指定してください') ;
	($upload_a and $upload_b) or print_html('ERROR : PDFが指定されていません') ;

	(-x $pdftotext_cmd) or print_html("ERROR : $pdftotext_cmd : not executable") ;
	(-x $uv_cmd) or print_html("ERROR : $uv_cmd : not executable") ;

	my $token = generate_token() ;
	my $workdir = "$tmpdir/$token" ;
	make_path($workdir) ;

	my $src_a = "$workdir/sourceA.pdf" ;
	my $src_b = "$workdir/sourceB.pdf" ;
	my $size_a = save_upload_file($upload_a, $src_a) ;
	my $size_b = save_upload_file($upload_b, $src_b) ;
	my $max_bytes = $pdf_max_mb * 1024 * 1024 ;
	$size_a <= $max_bytes or print_html("ERROR : pdfA too large (max ${pdf_max_mb}MB)") ;
	$size_b <= $max_bytes or print_html("ERROR : pdfB too large (max ${pdf_max_mb}MB)") ;

	my $xhtml_a = "$workdir/sourceA.xhtml" ;
	my $xhtml_b = "$workdir/sourceB.xhtml" ;
	my $stderr_log = "$workdir/pipeline.stderr.log" ;

	my ($ok_pdftotext_a, $msg_a) = run_command_timeout(
		[$pdftotext_cmd, '-bbox-layout', '-enc', 'UTF-8', $src_a, $xhtml_a],
		$pdftotext_timeout_sec,
		$stderr_log,
	) ;
	$ok_pdftotext_a or print_html("ERROR : pdftotext failed (A): $msg_a") ;

	my ($ok_pdftotext_b, $msg_b) = run_command_timeout(
		[$pdftotext_cmd, '-bbox-layout', '-enc', 'UTF-8', $src_b, $xhtml_b],
		$pdftotext_timeout_sec,
		$stderr_log,
	) ;
	$ok_pdftotext_b or print_html("ERROR : pdftotext failed (B): $msg_b") ;

	my $recon_a_json = "$workdir/reconstructA.json" ;
	my $recon_b_json = "$workdir/reconstructB.json" ;
	my @uv_base = get_uv_base_cmd() ;
	my ($ok_recon_a, $recon_msg_a) = run_command_timeout(
		[
			@uv_base, 'python', 'tools/pdf_annotate_diff.py',
			'--phase', 'reconstruct',
			'--input-xhtml', $xhtml_a,
			'--output-json', $recon_a_json,
		],
		$uv_timeout_sec,
		$stderr_log,
	) ;
	$ok_recon_a or print_html("ERROR : reconstruct failed (A): $recon_msg_a") ;

	my ($ok_recon_b, $recon_msg_b) = run_command_timeout(
		[
			@uv_base, 'python', 'tools/pdf_annotate_diff.py',
			'--phase', 'reconstruct',
			'--input-xhtml', $xhtml_b,
			'--output-json', $recon_b_json,
		],
		$uv_timeout_sec,
		$stderr_log,
	) ;
	$ok_recon_b or print_html("ERROR : reconstruct failed (B): $recon_msg_b") ;

	my $recon_a = load_json_file($recon_a_json) ;
	my $recon_b = load_json_file($recon_b_json) ;

	my $sequence_a = $recon_a->{'reconstructed_text'} // '' ;
	my $sequence_b = $recon_b->{'reconstructed_text'} // '' ;
	(length($sequence_a) <= $text_max_chars)
		or print_html("ERROR : extracted text too large (A > $text_max_chars)") ;
	(length($sequence_b) <= $text_max_chars)
		or print_html("ERROR : extracted text too large (B > $text_max_chars)") ;

	my @a_tokens = split_text( escape_char($sequence_a) ) ;
	my @b_tokens = split_text( escape_char($sequence_b) ) ;

	my $map_a = build_token_bbox_map_from_words($recon_a->{'words'} // []) ;
	my $map_b = build_token_bbox_map_from_words($recon_b->{'words'} // []) ;
	if (@$map_a != @a_tokens){
		print STDERR "WARN : map_a token size mismatch map=@{[scalar @$map_a]} seq=@{[scalar @a_tokens]}\\n" ;
		append_impl_log("WARN map_a token size mismatch map=@{[scalar @$map_a]} seq=@{[scalar @a_tokens]} token=$token") ;
	}
	if (@$map_b != @b_tokens){
		print STDERR "WARN : map_b token size mismatch map=@{[scalar @$map_b]} seq=@{[scalar @b_tokens]}\\n" ;
		append_impl_log("WARN map_b token size mismatch map=@{[scalar @$map_b]} seq=@{[scalar @b_tokens]} token=$token") ;
	}
	$map_a = normalize_token_map_size($map_a, scalar @a_tokens) ;
	$map_b = normalize_token_map_size($map_b, scalar @b_tokens) ;

	my $ctx = build_diff_context($sequence_a, $sequence_b) ;
	my ($deleted_ranges, $added_ranges, $ops) = parse_diff_ranges($ctx->{'diffsummary'}) ;

	my $annotate_input = {
		map_a          => $map_a,
		map_b          => $map_b,
		deleted_ranges => $deleted_ranges,
		added_ranges   => $added_ranges,
		ops            => $ops,
	} ;
	my $annotate_input_json = "$workdir/annotate_input.json" ;
	write_json_file($annotate_input_json, $annotate_input) ;

	my $ann_a = "$workdir/annotatedA.pdf" ;
	my $ann_b = "$workdir/annotatedB.pdf" ;
	my $ann_comment = "$workdir/annotatedComment.pdf" ;
	my $annotate_summary = "$workdir/annotate_summary.json" ;
	my ($ok_annotate, $annotate_msg) = run_command_timeout(
		[
			@uv_base, 'python', 'tools/pdf_annotate_diff.py',
			'--phase', 'annotate',
			'--source-a', $src_a,
			'--source-b', $src_b,
			'--input-json', $annotate_input_json,
			'--output-ann-a', $ann_a,
			'--output-ann-b', $ann_b,
			'--output-ann-comment', $ann_comment,
			'--summary-json', $annotate_summary,
		],
		$uv_timeout_sec,
		$stderr_log,
	) ;
	$ok_annotate or print_html("ERROR : annotate failed: $annotate_msg") ;

	my $summary = {} ;
	(-f $annotate_summary) and $summary = load_json_file($annotate_summary) ;
	append_impl_log(
		sprintf(
			"%s PDF annotate summary token=%s skipped_duplicates=%d map_a_miss=%d map_b_miss=%d",
			scalar localtime(),
			$token,
			$summary->{'skipped_duplicates'} // 0,
			$summary->{'map_a_missing'} // 0,
			$summary->{'map_b_missing'} // 0,
		)
	) ;

	my $table = $ctx->{'table'} ;
	my ($count1_A, $count2_A, $count3_A, $wcount_A) = count_char($sequence_a) ;
	my ($count1_B, $count2_B, $count3_B, $wcount_B) = count_char($sequence_b) ;
	$table .= <<"--EOS--" ;
<tr>
	<td><font color=gray>
		文字数: $count1_A<br>
		空白数: @{[$count2_A - $count1_A]} 空白込み文字数: $count2_A<br>
		改行数: @{[$count3_A - $count2_A]} 改行込み文字数: $count3_A<br>
		単語数: $wcount_A
	</font></td>
	<td><font color=gray>
		文字数: $count1_B<br>
		空白数: @{[$count2_B - $count1_B]} 空白込み文字数: $count2_B<br>
		改行数: @{[$count3_B - $count2_B]} 改行込み文字数: $count3_B<br>
		単語数: $wcount_B
	</font></td>
</tr>
--EOS--

	$sequenceA = $sequence_a ;
	$sequenceB = $sequence_b ;

	my $asset_root = "${data_url}tmp/$token" ;
	my $message = <<"--EOS--" ;
<div id=result>
<table cellspacing=0>
$table</table>

<p>
	<input type=button id=hide value='結果のみ表示 (印刷用)' onclick='hideForm()'> |
	<input type=radio name=color value=1 onclick='setColor1()' checked>
		<span class=blue >カラー1</span>
	<input type=radio name=color value=2 onclick='setColor2()'>
		<span class=green>カラー2</span>
	<input type=radio name=color value=3 onclick='setColor3()'>
		<span class=black>モノクロ</span>
</p>

<p><b>PDF成果物:</b><br>
<a href='$asset_root/sourceA.pdf' target='_blank'>srcA.pdf</a> /
<a href='$asset_root/sourceB.pdf' target='_blank'>srcB.pdf</a> /
<a href='$asset_root/annotatedA.pdf' target='_blank'>annA.pdf</a> /
<a href='$asset_root/annotatedB.pdf' target='_blank'>annB.pdf</a> /
<a href='$asset_root/annotatedComment.pdf' target='_blank'>annComment.pdf</a>
</p>
</div>

<div id=save>
<hr><!-- ________________________________________ -->

<h4>この結果を公開する</h4>

<form method=POST id=save name=save action='${url}save.cgi'>
<input type=hidden name=mode value='pdf'>
<input type=hidden name=pdf_token value='$token'>
<p>この結果をﾃﾞｭﾌﾌサーバに保存し、公開用のURLを発行します。<br>
削除パスワードを設定しておけば、あとで消すこともできます。<br>
<b>公開期間は${retention_days}日間です。</b>公開期間を過ぎると自動的に削除されます。</p>

<table id=passwd>
<tr>
	<td class=n>削除バスワード：<input type=text name=passwd size=10 value=''></td>
	<td class=n>設定したパスワードは後で確認することが<br>できませんので必ず控えてください。</td>
</tr>
</table>

<input type=submit onclick='return savehtml();' value='結果を公開する'>

<p>「結果を公開する」を押さない限り、入力した文書などがサーバに保存されることはありません。<br>
この機能はテスト運用中のものです。予告なく提供を中止することがあります。</p>
</form>
</div>
--EOS--

	print_html($message) ;
} ;
# ====================
sub build_diff_context {
	my ($seq_a, $seq_b) = @_ ;

	my $fifopath_a = "$fifodir/difff.$$.A" ;
	my @a_split = split_text( escape_char($seq_a) ) ;
	my @a_raw = @a_split ;
	my $a_split = join("\n", @a_split) . "\n" ;
	fifo_send($a_split, $fifopath_a) ;

	my $fifopath_b = "$fifodir/difff.$$.B" ;
	my @b_split = split_text( escape_char($seq_b) ) ;
	my @b_raw = @b_split ;
	my $b_split = join("\n", @b_split) . "\n" ;
	fifo_send($b_split, $fifopath_b) ;

	(-e $diffcmd) or print_html("ERROR : $diffcmd : not found") ;
	(-x $diffcmd) or print_html("ERROR : $diffcmd : not executable") ;
	my @diffout = `$diffcmd -d $fifopath_a $fifopath_b` ;
	my @diffsummary = grep /(^[^<>-]|<\$>)/, @diffout ;

	my ($a_start, $a_end, $b_start, $b_end) = (0, 0, 0, 0) ;
	foreach (@diffsummary){
		if ($_ =~ /^((\d+),)?(\d+)c(\d+)(,(\d+))?$/){
			$a_end   = $3 || 0 ;
			$a_start = $2 || $a_end ;
			$b_start = $4 || 0 ;
			$b_end   = $6 || $b_start ;
			$a_split[$a_start - 1] = '<em>' . ($a_split[$a_start - 1] // '') ;
			$a_split[$a_end - 1]  .= '</em>' ;
			$b_split[$b_start - 1] = '<em>' . ($b_split[$b_start - 1] // '') ;
			$b_split[$b_end - 1]  .= '</em>' ;
		} elsif ($_ =~ /^((\d+),)?(\d+)d(\d+)(,(\d+))?$/){
			$a_end   = $3 || 0 ;
			$a_start = $2 || $a_end ;
			$b_start = $4 || 0 ;
			$b_end   = $6 || $b_start ;
			$a_split[$a_start - 1] = '<em>' . ($a_split[$a_start - 1] // '') ;
			$a_split[$a_end - 1]  .= '</em>' ;
		} elsif ($_ =~ /^((\d+),)?(\d+)a(\d+)(,(\d+))?$/){
			$a_end   = $3 || 0 ;
			$a_start = $2 || $a_end ;
			$b_start = $4 || 0 ;
			$b_end   = $6 || $b_start ;
			$b_split[$b_start - 1] = '<em>' . ($b_split[$b_start - 1] // '') ;
			$b_split[$b_end - 1]  .= '</em>' ;
		} elsif ($_ =~ /> <\$>/){
			my $i = ($a_start > 1) ? $a_start - 2 : 0 ;
			while ($i < @a_split and not $a_split[$i] =~ s/<\$>/<\$><\$>/){ $i ++ }
		} elsif ($_ =~ /< <\$>/){
			my $i = ($b_start > 1) ? $b_start - 2 : 0 ;
			while ($i < @b_split and not $b_split[$i] =~ s/<\$>/<\$><\$>/){ $i ++ }
		}
	}

	my $a_final = join '', @a_split ;
	my $b_final = join '', @b_split ;
	while ( $a_final =~ s{(<em>[^<>]*)<\$>(([^<>]|<\$>)*</em>)}{$1</em><\$><em>$2}g ){}
	while ( $b_final =~ s{(<em>[^<>]*)<\$>(([^<>]|<\$>)*</em>)}{$1</em><\$><em>$2}g ){}
	my @a_final = split /<\$>/, $a_final ;
	my @b_final = split /<\$>/, $b_final ;
	my $par = (@a_final > @b_final) ? @a_final : @b_final ;
	my $table = '' ;
	foreach (0..$par-1){
		defined $a_final[$_] or $a_final[$_] = '' ;
		defined $b_final[$_] or $b_final[$_] = '' ;
		$a_final[$_] =~ s{(\ +</em>)}{escape_space($1)}ge ;
		$b_final[$_] =~ s{(\ +</em>)}{escape_space($1)}ge ;
		$table .=
"<tr>
	<td>$a_final[$_]</td>
	<td>$b_final[$_]</td>
</tr>
" ;
	}

	return {
		table       => $table,
		diffsummary => \@diffsummary,
		a_tokens    => \@a_raw,
		b_tokens    => \@b_raw,
	} ;
} ;
# ====================
sub parse_diff_ranges {
	my $diffsummary = $_[0] // [] ;
	my @deleted ;
	my @added ;
	my @ops ;
	foreach my $line (@$diffsummary){
		if ($line =~ /^((\d+),)?(\d+)c(\d+)(,(\d+))?$/){
			my $a_end   = $3 || 0 ;
			my $a_start = $2 || $a_end ;
			my $b_start = $4 || 0 ;
			my $b_end   = $6 || $b_start ;
			push @deleted, [$a_start - 1, $a_end - 1] ;
			push @added,   [$b_start - 1, $b_end - 1] ;
			push @ops, {
				type    => 'c',
				a_start => $a_start - 1,
				a_end   => $a_end - 1,
				b_start => $b_start - 1,
				b_end   => $b_end - 1,
			} ;
		} elsif ($line =~ /^((\d+),)?(\d+)d(\d+)(,(\d+))?$/){
			my $a_end   = $3 || 0 ;
			my $a_start = $2 || $a_end ;
			my $b_start = $4 || 0 ;
			push @deleted, [$a_start - 1, $a_end - 1] ;
			push @ops, {
				type    => 'd',
				a_start => $a_start - 1,
				a_end   => $a_end - 1,
				b_start => $b_start - 1,
				b_end   => $b_start - 1,
			} ;
		} elsif ($line =~ /^((\d+),)?(\d+)a(\d+)(,(\d+))?$/){
			my $a_end   = $3 || 0 ;
			my $a_start = $2 || $a_end ;
			my $b_start = $4 || 0 ;
			my $b_end   = $6 || $b_start ;
			push @added, [$b_start - 1, $b_end - 1] ;
			push @ops, {
				type    => 'a',
				a_start => $a_start - 1,
				a_end   => $a_end - 1,
				b_start => $b_start - 1,
				b_end   => $b_end - 1,
			} ;
		}
	}
	return (\@deleted, \@added, \@ops) ;
} ;
# ====================
sub build_token_bbox_map_from_words {
	my $words = $_[0] // [] ;
	my @map ;
	my $size = scalar @$words ;
	foreach my $i (0..$size-1){
		my $word = $words->[$i] ;
		my @tokens = split_text( escape_char($word->{'text'} // '') ) ;
		foreach my $token (@tokens){
			push @map, {
				page     => $word->{'page'},
				line_seq => $word->{'line_seq'},
				word_seq => $word->{'word_seq'},
				bbox     => $word->{'bbox'},
				token    => $token,
			} ;
		}
		if ($i < $size - 1){
			my $next_word = $words->[$i + 1] ;
			my $same_page = (($word->{'page'} // '') eq ($next_word->{'page'} // '')) ? 1 : 0 ;
			my $line_changed = (($word->{'line_seq'} // '') ne ($next_word->{'line_seq'} // '')) ? 1 : 0 ;
			($same_page and $line_changed) and push @map, undef ;  # 改行トークンはbboxを持たない
		}
	}
	return \@map ;
} ;
# ====================
sub normalize_token_map_size {
	my $map = $_[0] // [] ;
	my $target_size = $_[1] // 0 ;
	my @normalized = @$map ;
	while (@normalized < $target_size){
		push @normalized, undef ;
	}
	if (@normalized > $target_size){
		@normalized = @normalized[0..$target_size-1] ;
	}
	return \@normalized ;
} ;
# ====================
sub save_upload_file {
	my ($fh, $path) = @_ ;
	open my $out, '>', $path or print_html("ERROR : cannot write $path") ;
	binmode $out ;
	binmode $fh ;
	my $size = 0 ;
	my $chunk = '' ;
	while (read($fh, $chunk, 8192)){
		print {$out} $chunk ;
		$size += length($chunk) ;
	}
	close $out ;
	return $size ;
} ;
# ====================
sub run_command_timeout {
	my ($cmd_ref, $timeout, $stderr_path) = @_ ;
	my $pid = fork ;
	defined $pid or return (0, 'fork failed') ;
	if ($pid == 0){
		if ($stderr_path){
			open STDERR, '>>', $stderr_path or exit 127 ;
		}
		exec @$cmd_ref ;
		exit 127 ;
	}
	my $timed_out = 0 ;
	local $SIG{ALRM} = sub {
		$timed_out = 1 ;
		kill 'TERM', $pid ;
	} ;
	alarm($timeout) ;
	waitpid($pid, 0) ;
	alarm(0) ;
	if ($timed_out){
		kill 'KILL', $pid ;
		waitpid($pid, 0) ;
		return (0, 'timeout') ;
	}
	return ($? == 0, "exit=$?") ;
} ;
# ====================
sub get_uv_base_cmd {
	my @cmd = ($uv_cmd, 'run', '--project', 'tools', '--offline', '--no-python-downloads') ;
	if (defined $ENV{'UV_PYTHON'} and $ENV{'UV_PYTHON'} ne ''){
		push @cmd, '--no-managed-python' ;
	}
	return @cmd ;
} ;
# ====================
sub load_json_file {
	my $path = $_[0] // '' ;
	open my $fh, '<', $path or print_html("ERROR : cannot read $path") ;
	local $/ = undef ;
	my $json = <$fh> ;
	close $fh ;
	return decode_json($json) ;
} ;
# ====================
sub write_json_file {
	my ($path, $data) = @_ ;
	open my $fh, '>', $path or print_html("ERROR : cannot write $path") ;
	print {$fh} JSON::PP->new->utf8->canonical->encode($data) ;
	close $fh ;
} ;
# ====================
sub cleanup_tmp_artifacts {
	(-d $tmpdir) or return ;
	my $threshold = time - ($tmp_ttl_minutes * 60) ;
	opendir my $dh, $tmpdir or return ;
	while (my $entry = readdir $dh){
		next if $entry =~ /^\./ ;
		my $path = "$tmpdir/$entry" ;
		next unless -d $path ;
		my $mtime = (stat($path))[9] // time ;
		next if $mtime >= $threshold ;
		remove_tree($path) ;
	}
	closedir $dh ;
} ;
# ====================
sub append_impl_log {
	my $line = $_[0] // '' ;
	my $dir = 'docs' ;
	(-d $dir) or make_path($dir) ;
	open my $fh, '>>', "$dir/implementation-log.md" or return ;
	print {$fh} "$line\n" ;
	close $fh ;
} ;
# ====================
sub generate_token {
	my @chars = ('a'..'k', 'm', 'n', 'p'..'z', '2'..'9') ;
	return join '', map { $chars[int(rand(@chars))] } (1..12) ;
} ;
# ====================
sub get_env_int {
	my ($name, $default) = @_ ;
	defined $ENV{$name} or return $default ;
	$ENV{$name} =~ /^(\d+)$/ or return $default ;
	return $1 ;
} ;
# ====================
sub resolve_base_url {
	if (defined $ENV{'DIFFF_BASE_URL'} and $ENV{'DIFFF_BASE_URL'} ne ''){
		my $base = $ENV{'DIFFF_BASE_URL'} ;
		$base .= '/' unless $base =~ m{/$} ;
		return $base ;
	}
	if (defined $ENV{'HTTP_HOST'} and $ENV{'HTTP_HOST'} ne ''){
		my $scheme = 'http' ;
		if (defined $ENV{'REQUEST_SCHEME'} and lc($ENV{'REQUEST_SCHEME'}) eq 'https'){
			$scheme = 'https' ;
		} elsif (defined $ENV{'HTTPS'} and $ENV{'HTTPS'} =~ /^(1|on)$/i){
			$scheme = 'https' ;
		} elsif (defined $ENV{'SERVER_PORT'} and $ENV{'SERVER_PORT'} =~ /^443$/){
			$scheme = 'https' ;
		}
		my $script = $ENV{'SCRIPT_NAME'} // '/' ;
		$script =~ s/\?.*$// ;
		$script =~ s{[^/]*$}{} ;
		$script eq '' and $script = '/' ;
		return "${scheme}://$ENV{'HTTP_HOST'}$script" ;
	}
	if (defined $ENV{'SCRIPT_NAME'} and $ENV{'SCRIPT_NAME'} ne ''){
		my $script = $ENV{'SCRIPT_NAME'} ;
		$script =~ s/\?.*$// ;
		$script =~ s{[^/]*$}{} ;
		$script eq '' and $script = '/' ;
		return $script ;
	}
	return './' ;
} ;
# ====================
sub build_data_url {
	my $base = $_[0] // './' ;
	$base =~ s{(cgi-bin|htbin)/$}{} ;
	$base =~ m{/$} and return "${base}data/" ;
	return "${base}/data/" ;
} ;
# ====================
sub get_query_parameters {  # CGIが受け取ったパラメータの処理
my $buffer = '' ;
if (defined $ENV{'REQUEST_METHOD'} and
	$ENV{'REQUEST_METHOD'} eq 'POST' and
	defined $ENV{'CONTENT_LENGTH'}
){
	eval 'read(STDIN, $buffer, $ENV{"CONTENT_LENGTH"})' or
	print_html('ERROR : get_query_parameters() : read failed') ;
} elsif (defined $ENV{'QUERY_STRING'}){
	$buffer = $ENV{'QUERY_STRING'} ;
}
length $buffer > 5000000 and print_html('ERROR : input too large') ;
my %query ;
my @query = split /&/, $buffer ;
foreach (@query){
	my ($name, $value) = split /=/ ;
	if (defined $name and defined $value){
		$value =~ tr/+/ / ;
		$value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack('C', hex($1))/eg ;
		$name  =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack('C', hex($1))/eg ;
		$query{$name} = $value ;
	}
}
return %query ;
} ;
# ====================
sub split_text {  # 比較する単位ごとに文字列を分割してリストに格納
my $text = join('', @_) // '' ;
$text =~ s/\n/<\$>/g ;  # もともとの改行を <$> に変換して処理
my @text ;
while ($text =~ s/^([a-z]+|<\$>|&\#?\w+;|.)//){
	push @text, $1 ;
}
return @text ;
} ;
# ====================
sub fifo_send {  # usage: fifo_send($text, $path) ;
my $text = $_[0] // '' ;
my $path = $_[1] or print_html('ERROR : open failed (1)') ;
mkfifo($path, 0600) or print_html('ERROR : open failed (2)') ;
my $pid = fork ;
if ($pid == 0){
	open(FIFO, ">$path") or print_html('ERROR : open failed (3)') ;
	utf8::encode($text) ;  # UTF-8エンコード
	print FIFO $text ;
	close FIFO ;
	unlink $path ;
	exit ;
}
} ;
# ====================
sub escape_char {  # < > & ' " の5文字を実態参照に変換
my $string = $_[0] // '' ;
$string =~ s/\&/&amp;/g ;
$string =~ s/</&lt;/g ;
$string =~ s/>/&gt;/g ;
$string =~ s/\'/&#39;/g ;
$string =~ s/\"/&quot;/g ;
return $string ;
} ;
# ====================
sub escape_space {  # 空白文字を実態参照に変換
my $string = $_[0] // '' ;
$string =~ s/\s/&nbsp;/g ;  # 空白文字（スペース、タブ等含む）はスペースとみなす
return $string ;
} ;
# ====================
sub count_char {  # 文字数をカウント

#- ▼ メモ
# $count1: 改行空白なし文字数
# $count2: 空白あり文字数
# $count3: 改行空白あり文字数
# $wcount: 単語数
#- ▲ メモ

my $text = $_[0] // '' ;

#- ▼ 単語数をカウント
my $words = $text ;
my $wcount = ($words =~ s/\s*\S+//g) ;
#- ▲ 単語数をカウント

#- ▼ 文字数をカウント
$text =~ tr/\r//d ;  # カウントの準備: CRを除去
my $count3 = length($text) ;
$text =~ tr/\n//d ;  # 改行を除去してカウント
my $count2 = length($text) ;
$text =~ s/\s//g ;   # 空白文字を除去してカウント
my $count1 = length($text) ;
#- ▲ 文字数をカウント

return ($count1, $count2, $count3, $wcount) ;
} ;
# ====================
sub print_html {  # HTMLを出力

#- ▼ メモ
# ・比較結果ページを出力（デフォルト）
# ・引数が ERROR で始まる場合はエラーページを出力
# ・引数がない場合はトップページを出力
#- ▲ メモ

my $message = $_[0] // '' ;

#- ▼ エラーページ：引数が ERROR で始まる場合
$message =~ s{^(ERROR.*)$}{<p><font color=red>$1</font></p>}s ;
#- ▲ エラーページ：引数が ERROR で始まる場合

#- ▼ トップページ：引数がない場合
(not $message) and $message = <<'--EOS--'
<div id=news>
<p>新着情報：</p>

<ul>
	<li>2017-08-07　HTTPSによる暗号化通信に対応 -
		<a href='https://difff.jp/'>https://difff.jp/</a>
	<li>2015-06-17　ﾃﾞｭﾌﾌの結果を公開する機能を追加 (ver.6.1) -
		<a target='_blank' href='http://data.dbcls.jp/~meso/meme/archives/2957'>
			説明</a>
	<li>2014-03-14　トップページURLを <a href='http://difff.jp/'>http://difff.jp/</a> に変更
	<li>2014-03-12　ITmediaニュース -
		<a target='_blank' href='http://www.itmedia.co.jp/news/articles/1403/12/news121.html'>
			STAP細胞問題で活躍、テキスト比較ツール「デュフフ」とは</a>
	<li>2013-12-12　使い方の動画 -
		<a target='_blank' href='http://togotv.dbcls.jp/20130828.html'>
			difff《ﾃﾞｭﾌﾌ》を使って文章の変更箇所を調べる</a>
	<li>2013-03-12　全面リニューアル (ver.6) -
		<a target='_blank' href='http://data.dbcls.jp/~meso/meme/archives/2313'>
			変更点</a>
	<li>2013-01-11　<a href='https://difff.jp/en/'>英語版</a> を公開
	<li>2012-10-22　ソースを公開 -
		<a target='_blank' href='https://github.com/meso-cacase/difff'>
			GitHub</a>
	<li>2012-04-16　GIGAZINE -
		<a target='_blank' href='http://gigazine.net/news/20120416-difff/'>
			日本語対応で簡単に差分が確認できるテキスト比較ツール「difff(ﾃﾞｭﾌﾌ)」</a>
	<li>2012-04-13　全面リニューアル。左右で段落がずれないようにした (ver.5)
	<li>2008-02-18　日本語対応 (ver.4)
	<li>2004-02-19　初代 difff 完成 (ver.1)
</ul>
</div>

<hr><!-- ________________________________________ -->

<p><font color=gray>Last modified on Apr 28, 2025 by
<a target='_blank' href='http://twitter.com/meso_cacase'>@meso_cacase</a>
</font></p>
--EOS--

and $sequenceA = <<'--EOS--'
下記の文章を比較してください。
   Betty Botter bought some butter, 
But, she said, this butter's bitter;
If I put it in my batter,
It will make my batter bitter,
But a bit of better butter
Will make my batter better.
So she bought a bit of butter
Better than her bitter butter,
And she put it in her batter,
And it made her batter better,
So 'twas better Betty Botter
Bought a bit of better butter.
--EOS--

and $sequenceB = <<'--EOS--' ;
下記の文章を，ﾋﾋ較してくだちい．
Betty Botter bought some butter,
But, she said, the butter's bitter;
If I put it in my batter,
That will make my batter bitter.
But a bit of better butter, 
That will make my batter better.
So she bought a bit of butter
Better than her bitter butter.
And she put it in her batter,
And it made her batter better.
So it was better Betty Botter
Bought a bit of better butter.
--EOS--
#- ▲ トップページ：引数がない場合

#- ▼ HTML出力
$sequenceA = escape_char($sequenceA) ;  # XSS対策
$sequenceB = escape_char($sequenceB) ;  # XSS対策

my $html = <<"--EOS--" ;
<!DOCTYPE HTML PUBLIC '-//W3C//DTD HTML 4.01 Transitional//EN'>
<html lang=ja>

<head>
<meta http-equiv='Content-Type' content='text/html; charset=utf-8'>
<meta http-equiv='Content-Script-Type' content='text/javascript'>
<meta http-equiv='Content-Style-Type' content='text/css'>
<meta name='author' content='Yuki Naito'>
<title>difff《ﾃﾞｭﾌﾌ》</title>
<script type='text/javascript'>
<!--
	function hideForm() {
		if (document.getElementById('form').style.display == 'none') {
			document.getElementById('top' ).style.display = 'block';
			document.getElementById('form').style.display = 'block';
			document.getElementById('save').style.display = 'block';
			document.getElementById('hide').value = '結果のみ表示 (印刷用)';
		} else {
			document.getElementById('top' ).style.display = 'none';
			document.getElementById('form').style.display = 'none';
			document.getElementById('save').style.display = 'none';
			document.getElementById('hide').value = '全体を表示';
		}
	}
	function setColor1() {
		document.getElementById('top').style.borderTop = '5px solid #00BBFF';
		var emList = document.getElementsByTagName('em');
		for (i = 0; i < emList.length; i++) {
			emList[i].className = 'blue' ;
		}
	}
	function setColor2() {
		document.getElementById('top').style.borderTop = '5px solid #00bb00';
		var emList = document.getElementsByTagName('em');
		for (i = 0; i < emList.length; i++) {
			emList[i].className = 'green' ;
		}
	}
	function setColor3() {
		document.getElementById('top').style.borderTop = '5px solid black';
		var emList = document.getElementsByTagName('em');
		for (i = 0; i < emList.length; i++) {
			emList[i].className = 'black' ;
		}
	}
	function savehtml() {
		var element1 = document.createElement('input');
		element1.setAttribute('type', 'hidden');
		element1.setAttribute('name', 'sequenceA');
		element1.setAttribute('value', document.difff.sequenceA.value);
		document.save.appendChild(element1);

		var element2 = document.createElement('input');
		element2.setAttribute('type', 'hidden');
		element2.setAttribute('name', 'sequenceB');
		element2.setAttribute('value', document.difff.sequenceB.value);
		document.save.appendChild(element2);

		return confirm('本当に公開してもいいですか？\\n[OK] → 結果を公開し、そのページに移動します。');
	}
//-->
</script>
<style type='text/css'>
<!--
	* { font-family:verdana,arial,helvetica,sans-serif }
	p,table,textarea,ul { font-size:10pt }
	textarea { width:100% }
	a  { color:#3366CC }
	.k { color:black; text-decoration:none }
	em { font-style:normal }
	em,
	.blue  { font-weight:bold; color:black; background:#99EEFF; border:1px solid #00BBFF }
	.green { font-weight:bold; color:black; background:#99FF99; border:none }
	.black { font-weight:bold; color:white; background:black;   border:none }
	table {
		width:95%;
		margin:20px;
		table-layout:fixed;
		word-wrap:break-word;
		border-collapse:collapse;
	}
	td {
		padding:4px 15px;
		border-left:solid 1px silver;
		border-right:solid 1px silver;
	}
	table#passwd {
		width:auto;
		border:dotted 1px #8c93ba;
	}
	.n { border:none }
-->
</style>
</head>

<body>

<div id=top style='border-top:5px solid #00BBFF; padding-top:10px'>
<font size=5>
	<a class=k href='$url'>
	テキスト比較ツール difff《ﾃﾞｭﾌﾌ》</a></font><!--
--><font size=3>ver.6.1</font>
&emsp;
<font size=1 style='vertical-align:16px'>
	<a href='${url}en/'>English</a> |
	Japanese
</font>
&emsp;
<font size=1 style='vertical-align:16px'>
<a href='${url}v5/'>旧バージョン (ver.5)</a>
</font>
<hr><!-- ________________________________________ -->
</div>

<div id=form>
<p>下の枠に比較したい文章を入れてくだちい。差分 (diff) を表示します。</p>

<form method=POST id=difff name=difff action='${url}difff.pl'>
<table cellspacing=0>
<tr>
	<td class=n><textarea name=sequenceA rows=20>$sequenceA</textarea></td>
	<td class=n><textarea name=sequenceB rows=20>$sequenceB</textarea></td>
</tr>
</table>

<p><input type=submit value='比較する'></p>
</form>

<hr>
<p>PDF同士を比較する場合は、下のフォームから2つのPDFを選択してください。</p>
<form method=POST id=pdfdiff name=pdfdiff action='${url}difff.pl' enctype='multipart/form-data'>
<input type=hidden name=mode value='pdf'>
<table cellspacing=0>
<tr>
	<td class=n>PDF A: <input type=file name=pdfA accept='application/pdf'></td>
	<td class=n>PDF B: <input type=file name=pdfB accept='application/pdf'></td>
</tr>
</table>
<p><input type=submit value='PDFを比較する'></p>
</form>
</div>

$message

</body>
</html>
--EOS--

print "Content-type: text/html; charset=utf-8\n\n$html" ;
#- ▲ HTML出力

exit ;
} ;
# ====================
