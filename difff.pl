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
# 2026-02-19 UI統合リデザイン + 公開機能廃止 + Electron連携前提の構成へ更新

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
my $tmp_ttl_minutes           = get_env_int('DIFFF_TMP_TTL_MINUTES', 120) ;
my $pdftotext_timeout_sec     = get_env_int('DIFFF_PDFTOTEXT_TIMEOUT_SEC', 60) ;
my $uv_timeout_sec            = get_env_int('DIFFF_UV_TIMEOUT_SEC', 60) ;
my $diff_bridge_chars         = get_env_int('DIFFF_DIFF_BRIDGE_CHARS', 2) ;
my $pdftotext_cmd             = $ENV{'DIFFF_PDFTOTEXT_CMD'} // '/opt/homebrew/bin/pdftotext' ;
my $uv_cmd                    = $ENV{'DIFFF_UV_CMD'} // '/opt/homebrew/bin/uv' ;
my $data_url                  = build_data_url($url) ;
my $static_url                = build_static_url($url) ;

binmode STDOUT, ':utf8' ;        # 標準出力をUTF-8エンコード
binmode STDERR, ':utf8' ;        # 標準エラー出力をUTF-8エンコード

my $sequenceA = '' ;
my $sequenceB = '' ;
my $cgi = CGI->new ;

cleanup_tmp_artifacts() ;

$sequenceA = $cgi->param('sequenceA') // '' ;
$sequenceB = $cgi->param('sequenceB') // '' ;
utf8::decode($sequenceA) unless utf8::is_utf8($sequenceA) ;
utf8::decode($sequenceB) unless utf8::is_utf8($sequenceB) ;

my $upload_a = $cgi->upload('pdfA') ;
my $upload_b = $cgi->upload('pdfB') ;
my $has_pdf_a = defined $upload_a ;
my $has_pdf_b = defined $upload_b ;
my $has_text  = ($sequenceA ne '' or $sequenceB ne '') ;

(length($sequenceA) <= $text_max_chars)
	or print_html("ERROR : input too large (A > $text_max_chars)") ;
(length($sequenceB) <= $text_max_chars)
	or print_html("ERROR : input too large (B > $text_max_chars)") ;

if (($has_pdf_a and not $has_pdf_b) or (not $has_pdf_a and $has_pdf_b)){
	print_html('ERROR : 2つのPDFを指定してください') ;
}

if ($has_pdf_a and $has_pdf_b){
	process_pdf_request($cgi) ;
	exit ;
}

if ($has_text){
	process_text_request($sequenceA, $sequenceB) ;
	exit ;
}

print_html() ;
exit ;

# ====================
sub process_text_request {
	my ($seq_a, $seq_b) = @_ ;
	my $ctx = build_diff_context($seq_a, $seq_b) ;
	my $table = append_count_row($ctx->{'table'}, $seq_a, $seq_b) ;
	my $message = build_result_section(
		mode      => 'text',
		table     => $table,
		asset_root => '',
	) ;
	$sequenceA = $seq_a ;
	$sequenceB = $seq_b ;
	print_html($message) ;
} ;
# ====================
sub process_pdf_request {
	my $cgi = $_[0] // CGI->new ;

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
		deleted_bridge_chars => $diff_bridge_chars,
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
			"%s PDF annotate summary token=%s skipped_duplicates=%d map_a_miss=%d map_b_miss=%d comment_pages_extended=%d comment_min_font_used=%.1f comment_continuation_pages=%d comment_merged_groups=%d deleted_ranges_input=%d deleted_ranges_output=%d deleted_bridge_merges=%d",
			scalar localtime(),
			$token,
				$summary->{'skipped_duplicates'} // 0,
				$summary->{'map_a_missing'} // 0,
				$summary->{'map_b_missing'} // 0,
				$summary->{'comment_pages_extended'} // 0,
				$summary->{'comment_min_font_used'} // 0,
				$summary->{'comment_continuation_pages'} // 0,
				$summary->{'comment_merged_groups'} // 0,
				$summary->{'deleted_ranges_input'} // 0,
				$summary->{'deleted_ranges_output'} // 0,
				$summary->{'deleted_bridge_merges'} // 0,
			)
	) ;

	my $table = append_count_row($ctx->{'table'}, $sequence_a, $sequence_b) ;
	$sequenceA = $sequence_a ;
	$sequenceB = $sequence_b ;
	my $asset_root = "${data_url}tmp/$token" ;
	my $message = build_result_section(
		mode      => 'pdf',
		table     => $table,
		asset_root => $asset_root,
	) ;
	print_html($message) ;
} ;
# ====================
sub append_count_row {
	my ($table, $seq_a, $seq_b) = @_ ;
	$table //= '' ;
	$seq_a //= '' ;
	$seq_b //= '' ;
	my ($count1_A, $count2_A, $count3_A, $wcount_A) = count_char($seq_a) ;
	my ($count1_B, $count2_B, $count3_B, $wcount_B) = count_char($seq_b) ;
	$table .= <<"--EOS--" ;
<tr class='stats-row'>
	<td>
		<div class='stats-item'>字: $count1_A / 単語: $wcount_A</div>
		<div class='stats-item'>空白: @{[$count2_A - $count1_A]} / 改行: @{[$count3_A - $count2_A]}</div>
	</td>
	<td>
		<div class='stats-item'>字: $count1_B / 単語: $wcount_B</div>
		<div class='stats-item'>空白: @{[$count2_B - $count1_B]} / 改行: @{[$count3_B - $count2_B]}</div>
	</td>
</tr>
--EOS--
	return $table ;
} ;
# ====================
sub build_result_section {
	my %args = @_ ;
	my $mode = $args{'mode'} // 'text' ;
	my $table = $args{'table'} // '' ;
	my $asset_root = $args{'asset_root'} // '' ;
	my $mode_label = ($mode eq 'pdf') ? 'PDF' : 'Text' ;

	my $pdf_tools_html = '' ;
	if ($mode eq 'pdf' and $asset_root ne ''){
		$pdf_tools_html = <<"--EOS--" ;
	<div class='pdf-tools' aria-label='PDF成果物'>
		<div class='pdf-tools-title'><svg class='i'><use href='${static_url}icons.svg#icon-folder'></use></svg> pdf</div>
		<div class='pdf-tools-links'>
			<a href='$asset_root/sourceA.pdf' target='_blank' rel='noopener'>srcA</a>
			<a href='$asset_root/sourceB.pdf' target='_blank' rel='noopener'>srcB</a>
			<a href='$asset_root/annotatedA.pdf' target='_blank' rel='noopener'>annA</a>
			<a href='$asset_root/annotatedB.pdf' target='_blank' rel='noopener'>annB</a>
			<a href='$asset_root/annotatedComment.pdf' target='_blank' rel='noopener'>annComment</a>
		</div>
	</div>
--EOS--
	}

	return <<"--EOS--" ;
<section class='result-card' id='result-card' data-mode='$mode'>
		<div class='result-head'>
			<h2><svg class='i'><use href='${static_url}icons.svg#icon-diff'></use></svg> $mode_label</h2>
			<div class='result-tools'>
				<button type='button' class='icon-btn' id='print-view-btn' aria-label='結果のみ表示' title='結果のみ表示'>
					<svg class='i'><use href='${static_url}icons.svg#icon-focus'></use></svg>
				</button>
				$pdf_tools_html
			</div>
		</div>
		<div class='result-table-wrap'>
			<table class='diff-table' cellspacing='0'>
				$table
			</table>
		</div>
</section>
--EOS--
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
sub split_bbox_by_token_count {
	my ($bbox, $count) = @_ ;
	my @boxes ;
	($count and $count > 0) or return @boxes ;
	(ref $bbox eq 'HASH') or return @boxes ;
	(defined $bbox->{'x_min'} and defined $bbox->{'x_max'} and
	 defined $bbox->{'y_min'} and defined $bbox->{'y_max'}) or return @boxes ;

	my $x_min = 0 + $bbox->{'x_min'} ;
	my $x_max = 0 + $bbox->{'x_max'} ;
	my $y_min = 0 + $bbox->{'y_min'} ;
	my $y_max = 0 + $bbox->{'y_max'} ;
	my $width = $x_max - $x_min ;
	$width > 0 or return @boxes ;

	my $step = $width / $count ;
	foreach my $i (0..$count-1){
		my $left = $x_min + ($step * $i) ;
		my $right = ($i == $count - 1) ? $x_max : ($x_min + ($step * ($i + 1))) ;
		push @boxes, {
			x_min => $left,
			y_min => $y_min,
			x_max => $right,
			y_max => $y_max,
		} ;
	}
	return @boxes ;
} ;
# ====================
sub build_token_bbox_map_from_words {
	my $words = $_[0] // [] ;
	my @map ;
	my $size = scalar @$words ;
	foreach my $i (0..$size-1){
		my $word = $words->[$i] ;
		my @tokens = split_text( escape_char($word->{'text'} // '') ) ;
		my @token_boxes = split_bbox_by_token_count($word->{'bbox'}, scalar @tokens) ;
		foreach my $ti (0..$#tokens){
			my $token = $tokens[$ti] ;
			my $token_bbox = ($ti <= $#token_boxes) ? $token_boxes[$ti] : $word->{'bbox'} ;
			push @map, {
				page     => $word->{'page'},
				line_seq => $word->{'line_seq'},
				word_seq => $word->{'word_seq'},
				token_index => scalar(@map),
				bbox     => $word->{'bbox'},
				token_bbox => $token_bbox,
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
sub build_static_url {
	my $base = $_[0] // './' ;
	$base =~ s{(cgi-bin|htbin)/$}{} ;
	$base =~ m{/$} and return "${base}static/" ;
	return "${base}/static/" ;
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
	my $message = $_[0] // '' ;

	if ($message =~ /^(ERROR.*)$/s){
		$message = "<section class='result-card notice-card error'><h2>エラー</h2><p>$1</p></section>" ;
	}

	if (not $message){
		$message = <<"--EOS--" ;
<section class='result-card empty-card'>
	<h2><svg class='i'><use href='${static_url}icons.svg#icon-spark'></use></svg> Ready</h2>
</section>
--EOS--

		$sequenceA = <<'--EOS--' ;
契約書の改訂版を比較するときは、ここにA案を貼り付けます。
改行と空白も比較対象です。
--EOS--
		$sequenceB = <<'--EOS--' ;
契約書の改訂版を比較するときは、ここにB案を貼り付けます。
改行と空白も比較対象になります。
--EOS--
	}

	$sequenceA = escape_char($sequenceA // '') ;
	$sequenceB = escape_char($sequenceB // '') ;

	my $html = <<"--EOS--" ;
<!DOCTYPE html>
<html lang='ja'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<meta name='author' content='Yuki Naito'>
<title>difff-pdf</title>
<link rel='icon' href='${url}../favicon.ico'>
<link rel='stylesheet' href='${static_url}app.css'>
<script defer src='${static_url}app.js'></script>
</head>
<body class='theme-blue'>
<div class='app-shell' id='app-shell'>
		<header class='app-header' id='app-header'>
			<div class='brand'>
				<svg class='i i-lg'><use href='${static_url}icons.svg#icon-spark'></use></svg>
				<div>
					<h1>difff-pdf</h1>
				</div>
			</div>
		</header>

	<main class='app-main'>
			<section class='workspace-card' id='workspace-card'>
				<div class='workspace-head'>
					<h2><svg class='i'><use href='${static_url}icons.svg#icon-input'></use></svg> Input</h2>
				</div>
			<form method='POST' id='compare-form' name='compare' action='${url}difff.pl' enctype='multipart/form-data'>
				<div class='text-grid'>
					<label class='field-card' for='sequenceA'>
						<span class='field-title'>A</span>
						<textarea id='sequenceA' name='sequenceA' rows='13' placeholder='テキストA'>$sequenceA</textarea>
					</label>
					<label class='field-card' for='sequenceB'>
						<span class='field-title'>B</span>
						<textarea id='sequenceB' name='sequenceB' rows='13' placeholder='テキストB'>$sequenceB</textarea>
					</label>
				</div>
				<div class='pdf-grid'>
					<label class='file-card' for='pdfA'>
						<svg class='i'><use href='${static_url}icons.svg#icon-pdf'></use></svg>
						<span>PDF A</span>
						<input id='pdfA' type='file' name='pdfA' accept='application/pdf'>
					</label>
					<label class='file-card' for='pdfB'>
						<svg class='i'><use href='${static_url}icons.svg#icon-pdf'></use></svg>
						<span>PDF B</span>
						<input id='pdfB' type='file' name='pdfB' accept='application/pdf'>
					</label>
				</div>
				<div class='actions'>
					<button type='submit' class='primary-btn' aria-label='比較実行' title='比較実行'>
						<svg class='i'><use href='${static_url}icons.svg#icon-play'></use></svg>
						比較
					</button>
					<button type='button' class='ghost-btn' id='clear-btn' aria-label='入力クリア' title='入力クリア'>
						<svg class='i'><use href='${static_url}icons.svg#icon-erase'></use></svg>
						クリア
					</button>
				</div>
				</form>
			</section>

		$message
	</main>
</div>
</body>
</html>
--EOS--

	print "Content-type: text/html; charset=utf-8\n\n$html" ;
	exit ;
} ;
# ====================
