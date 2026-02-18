#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import json
import sys
from collections import defaultdict
from dataclasses import dataclass
from html.parser import HTMLParser
from io import BytesIO
from pathlib import Path
from typing import Any

from pypdf import PdfReader, PdfWriter
from reportlab.lib.colors import Color
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.pdfgen import canvas


COMMENT_MARGIN_WIDTH = 180.0
COMMENT_FONT_START = 7.0
COMMENT_FONT_MIN = 6.0
COMMENT_FONT_STEP = 0.5
COMMENT_MARGIN_PAD_X = 8.0
COMMENT_MARGIN_PAD_Y = 8.0
COMMENT_BOX_PAD_X = 3.0
COMMENT_BOX_PAD_Y = 2.0
COMMENT_BOX_GAP = 4.0
COMMENT_MERGE_GAP_PT = 8.0


@dataclass
class Word:
    page: int
    line_seq: int
    word_seq: int
    text: str
    bbox: dict[str, float] | None


class BboxLayoutParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self.page_idx = 0
        self.line_seq = -1
        self.word_seq_by_page: dict[int, int] = defaultdict(int)
        self.in_word = False
        self.word_attrs: dict[str, str] = {}
        self.word_buf: list[str] = []
        self.words: list[Word] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_map = {k.lower(): (v if v is not None else "") for k, v in attrs}
        if tag == "page":
            self.page_idx += 1
            self.line_seq = -1
        elif tag == "line":
            self.line_seq += 1
        elif tag == "word":
            self.in_word = True
            self.word_attrs = attrs_map
            self.word_buf = []

    def handle_data(self, data: str) -> None:
        if self.in_word:
            self.word_buf.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag != "word" or not self.in_word:
            return
        self.in_word = False
        text = "".join(self.word_buf)
        bbox = None
        keys = ("xmin", "ymin", "xmax", "ymax")
        if all(k in self.word_attrs for k in keys):
            try:
                bbox = {
                    "x_min": float(self.word_attrs["xmin"]),
                    "y_min": float(self.word_attrs["ymin"]),
                    "x_max": float(self.word_attrs["xmax"]),
                    "y_max": float(self.word_attrs["ymax"]),
                }
            except ValueError:
                bbox = None
        page_word_seq = self.word_seq_by_page[self.page_idx]
        self.word_seq_by_page[self.page_idx] += 1
        self.words.append(
            Word(
                page=self.page_idx,
                line_seq=self.line_seq,
                word_seq=page_word_seq,
                text=text,
                bbox=bbox,
            )
        )


def reconstruct_from_xhtml(input_xhtml: Path) -> dict[str, Any]:
    parser = BboxLayoutParser()
    parser.feed(input_xhtml.read_text(encoding="utf-8", errors="replace"))

    parts: list[str] = []
    prev_page: int | None = None
    prev_line: int | None = None
    for word in parser.words:
        if prev_page is not None:
            same_page = prev_page == word.page
            line_changed = prev_line != word.line_seq
            if same_page and line_changed:
                parts.append("\n")
        parts.append(word.text)
        prev_page = word.page
        prev_line = word.line_seq

    reconstructed_text = "".join(parts)
    words_payload = [
        {
            "page": w.page,
            "line_seq": w.line_seq,
            "word_seq": w.word_seq,
            "text": w.text,
            "bbox": w.bbox,
        }
        for w in parser.words
    ]
    return {"reconstructed_text": reconstructed_text, "words": words_payload}


def quantize_bbox_key(page: int, bbox: dict[str, float] | None) -> str:
    if not bbox:
        return f"{page}:none"
    return (
        f"{page}:{int(round(bbox['x_min']*10))}:"
        f"{int(round(bbox['y_min']*10))}:{int(round(bbox['x_max']*10))}:"
        f"{int(round(bbox['y_max']*10))}"
    )


def dedupe_draw_entries(entries: list[dict[str, Any]], kind: str, stats: dict[str, int]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    uniq: list[dict[str, Any]] = []
    for e in entries:
        page = int(e.get("page") or 0)
        word_seq = e.get("word_seq")
        if word_seq is None:
            key = f"{kind}:{quantize_bbox_key(page, e.get('bbox'))}"
        else:
            key = f"{kind}:{page}:{word_seq}"
        if key in seen:
            stats["skipped_duplicates"] = stats.get("skipped_duplicates", 0) + 1
            continue
        seen.add(key)
        uniq.append(e)
    return uniq


def range_to_indices(ranges: list[list[int]]) -> list[int]:
    out: list[int] = []
    for pair in ranges:
        if not isinstance(pair, list) or len(pair) != 2:
            continue
        start, end = int(pair[0]), int(pair[1])
        if end < start:
            continue
        out.extend(range(start, end + 1))
    return out


def map_entries_for_indices(
    token_map: list[Any],
    indices: list[int],
    stats: dict[str, int],
    missing_key: str,
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for idx in indices:
        if idx < 0 or idx >= len(token_map):
            stats[missing_key] = stats.get(missing_key, 0) + 1
            continue
        item = token_map[idx]
        if not item or not item.get("bbox"):
            stats[missing_key] = stats.get(missing_key, 0) + 1
            continue
        out.append(item)
    return out


def ensure_fonts() -> tuple[str, str]:
    regular = "HeiseiKakuGo-W5"
    bold = "HeiseiKakuGo-W5"
    try:
        pdfmetrics.registerFont(UnicodeCIDFont(regular))
    except Exception:
        regular = "Helvetica"
        bold = "Helvetica-Bold"
    return regular, bold


def bbox_to_pdf_coords(page_h: float, bbox: dict[str, float]) -> tuple[float, float, float, float]:
    x0 = float(bbox["x_min"])
    x1 = float(bbox["x_max"])
    y0 = page_h - float(bbox["y_max"])
    y1 = page_h - float(bbox["y_min"])
    return x0, y0, x1, y1


def draw_text(c: canvas.Canvas, x: float, y: float, text: str, font: str, size: float) -> None:
    c.setFont(font, size)
    c.drawString(x, y, text)


def marker_key_for_anchor(anchor: dict[str, Any]) -> str:
    page = int(anchor.get("page") or 0)
    word_seq = anchor.get("word_seq")
    if word_seq is None:
        return f"{page}:{quantize_bbox_key(page, anchor.get('bbox'))}"
    return f"{page}:{word_seq}"


def iter_font_sizes(start: float, minimum: float, step: float) -> list[float]:
    out: list[float] = []
    value = start
    while value >= (minimum - 1e-6):
        out.append(round(value, 2))
        value -= step
    return out


def wrap_text_by_width(text: str, font_name: str, font_size: float, max_width: float) -> list[str]:
    if not text:
        return [""]
    parts = text.replace("\r", "").split("\n")
    lines: list[str] = []
    for part in parts:
        if part == "":
            lines.append("")
            continue
        cur = ""
        for ch in part:
            candidate = cur + ch
            if cur and pdfmetrics.stringWidth(candidate, font_name, font_size) > max_width:
                lines.append(cur)
                cur = ch
            else:
                cur = candidate
        if cur:
            lines.append(cur)
    return lines or [""]


def get_font_metrics(font_name: str, font_size: float) -> tuple[float, float, float, float]:
    ascent = float(pdfmetrics.getAscent(font_name, font_size))
    descent = abs(float(pdfmetrics.getDescent(font_name, font_size)))
    glyph_h = max(1.0, ascent + descent)
    line_step = max(glyph_h + 1.0, font_size + 2.0)
    return ascent, descent, glyph_h, line_step


def collect_comment_text_from_map(map_b: list[Any], start_idx: int, end_idx: int) -> str:
    if end_idx < start_idx:
        return ""
    lower = max(0, int(start_idx))
    upper = min(int(end_idx), len(map_b) - 1)
    if upper < lower:
        return ""
    tokens: list[str] = []
    for i in range(lower, upper + 1):
        item = map_b[i]
        if not item:
            continue
        tok = item.get("token")
        if not tok:
            continue
        tok_str = str(tok)
        if tok_str == "<$>":
            continue
        tokens.append(html.unescape(tok_str))
    return "".join(tokens)


def build_comment_annotations(ops: list[dict[str, Any]], map_a: list[Any], map_b: list[Any], stats: dict[str, int]) -> list[dict[str, Any]]:
    annotations: list[dict[str, Any]] = []

    def nearest_anchor(op: dict[str, Any]) -> dict[str, Any] | None:
        candidates = [
            op.get("a_start"),
            op.get("a_end"),
            (op.get("a_start") or 0) - 1,
            (op.get("a_end") or 0) + 1,
        ]
        for idx in candidates:
            if idx is None:
                continue
            idx = int(idx)
            if idx < 0 or idx >= len(map_a):
                continue
            item = map_a[idx]
            if item and item.get("bbox"):
                return item
        return None

    for op in ops:
        typ = op.get("type")
        if typ not in {"a", "c"}:
            continue
        b_start = int(op.get("b_start", -1))
        b_end = int(op.get("b_end", -1))
        if b_start < 0 or b_end < b_start:
            continue
        text = collect_comment_text_from_map(map_b, b_start, b_end).strip()
        if not text:
            continue
        anchor = nearest_anchor(op)
        if not anchor:
            stats["map_a_missing"] = stats.get("map_a_missing", 0) + 1
            continue
        annotations.append(
            {
                "anchor": anchor,
                "text": text,
                "b_start": b_start,
                "b_end": b_end,
            }
        )

    uniq: list[dict[str, Any]] = []
    seen: set[str] = set()
    for ann in annotations:
        anchor = ann["anchor"]
        page = int(anchor.get("page") or 0)
        word_seq = anchor.get("word_seq")
        b_start = int(ann.get("b_start", -1))
        b_end = int(ann.get("b_end", -1))
        key = f"comment:{page}:{word_seq}:{b_start}:{b_end}:{ann['text']}"
        if key in seen:
            stats["skipped_duplicates"] = stats.get("skipped_duplicates", 0) + 1
            continue
        seen.add(key)
        uniq.append(ann)
    return merge_nearby_comment_annotations(uniq, map_b, stats)


def merge_nearby_comment_annotations(
    annotations: list[dict[str, Any]],
    map_b: list[Any],
    stats: dict[str, int],
) -> list[dict[str, Any]]:
    if len(annotations) <= 1:
        return annotations

    def sort_key(ann: dict[str, Any]) -> tuple[int, int, int, float]:
        anchor = ann["anchor"]
        page = int(anchor.get("page") or 0)
        line_seq = int(anchor.get("line_seq") or 0)
        word_seq = int(anchor.get("word_seq") or 0)
        bbox = anchor.get("bbox") or {}
        x_min = float(bbox.get("x_min") or 0.0)
        return (page, line_seq, word_seq, x_min)

    def can_merge(prev: dict[str, Any], nxt: dict[str, Any]) -> bool:
        a_prev = prev["anchor"]
        a_next = nxt["anchor"]
        if int(a_prev.get("page") or 0) != int(a_next.get("page") or 0):
            return False
        if int(a_prev.get("line_seq") or 0) != int(a_next.get("line_seq") or 0):
            return False
        b_prev = a_prev.get("bbox")
        b_next = a_next.get("bbox")
        if not b_prev or not b_next:
            return False
        gap = float(b_next.get("x_min") or 0.0) - float(b_prev.get("x_max") or 0.0)
        return gap <= COMMENT_MERGE_GAP_PT

    def new_group(src: dict[str, Any]) -> dict[str, Any]:
        anchor = dict(src["anchor"])
        if anchor.get("bbox"):
            anchor["bbox"] = dict(anchor["bbox"])
        return {
            "anchor": anchor,
            "b_start": int(src.get("b_start", -1)),
            "b_end": int(src.get("b_end", -1)),
        }

    ordered = sorted(annotations, key=sort_key)
    grouped: list[dict[str, Any]] = []
    current = new_group(ordered[0])
    merged_count = 0

    for ann in ordered[1:]:
        candidate = {"anchor": current["anchor"]}
        if can_merge(candidate, ann):
            merged_count += 1
            current["b_start"] = min(int(current.get("b_start", -1)), int(ann.get("b_start", -1)))
            current["b_end"] = max(int(current.get("b_end", -1)), int(ann.get("b_end", -1)))
            b_cur = current["anchor"].get("bbox")
            b_new = ann["anchor"].get("bbox")
            if b_cur and b_new:
                b_cur["x_min"] = min(float(b_cur.get("x_min") or 0.0), float(b_new.get("x_min") or 0.0))
                b_cur["y_min"] = min(float(b_cur.get("y_min") or 0.0), float(b_new.get("y_min") or 0.0))
                b_cur["x_max"] = max(float(b_cur.get("x_max") or 0.0), float(b_new.get("x_max") or 0.0))
                b_cur["y_max"] = max(float(b_cur.get("y_max") or 0.0), float(b_new.get("y_max") or 0.0))
            cur_word = current["anchor"].get("word_seq")
            new_word = ann["anchor"].get("word_seq")
            if cur_word is None:
                current["anchor"]["word_seq"] = new_word
            elif new_word is not None:
                current["anchor"]["word_seq"] = min(int(cur_word), int(new_word))
            continue
        grouped.append(current)
        current = new_group(ann)

    grouped.append(current)
    if merged_count > 0:
        stats["comment_merged_groups"] = stats.get("comment_merged_groups", 0) + merged_count

    result: list[dict[str, Any]] = []
    for g in grouped:
        text = collect_comment_text_from_map(map_b, int(g.get("b_start", -1)), int(g.get("b_end", -1))).strip()
        if not text:
            continue
        result.append({"anchor": g["anchor"], "text": text})
    return result


def merge_overlay(
    base_pdf: Path,
    out_pdf: Path,
    draw_plan: dict[int, dict[str, Any]],
    regular_font: str,
    bold_font: str,
) -> None:
    del regular_font, bold_font
    base_reader = PdfReader(str(base_pdf))
    buf = BytesIO()

    first_w = float(base_reader.pages[0].mediabox.width)
    first_h = float(base_reader.pages[0].mediabox.height)
    c = canvas.Canvas(buf, pagesize=(first_w, first_h))

    for i, page in enumerate(base_reader.pages):
        page_num = i + 1
        w = float(page.mediabox.width)
        h = float(page.mediabox.height)
        c.setPageSize((w, h))

        plan = draw_plan.get(page_num, {})
        for entry in plan.get("strike", []):
            x0, y0, x1, y1 = bbox_to_pdf_coords(h, entry["bbox"])
            y = (y0 + y1) / 2.0
            c.setStrokeColor(Color(0.86, 0.10, 0.10, alpha=0.9))
            c.setLineWidth(1.2)
            c.line(x0, y, x1, y)

        for entry in plan.get("mark", []):
            x0, y0, x1, y1 = bbox_to_pdf_coords(h, entry["bbox"])
            c.setStrokeColor(Color(0.12, 0.45, 0.12, alpha=0.95))
            c.setLineWidth(0.8)
            c.rect(x0, y0, max(0.8, x1 - x0), max(0.8, y1 - y0), stroke=1, fill=0)

        c.showPage()

    c.save()
    buf.seek(0)
    overlay_reader = PdfReader(buf)

    writer = PdfWriter()
    for i, page in enumerate(base_reader.pages):
        if i < len(overlay_reader.pages):
            page.merge_page(overlay_reader.pages[i])
        writer.add_page(page)

    with out_pdf.open("wb") as f:
        writer.write(f)


def comment_anchor_center_y(anchor: dict[str, Any], page_h: float) -> float:
    _, y0, _, y1 = bbox_to_pdf_coords(page_h, anchor["bbox"])
    return (y0 + y1) / 2.0


def sort_comments_by_anchor(comments: list[dict[str, Any]], page_h: float) -> list[dict[str, Any]]:
    return sorted(comments, key=lambda ann: comment_anchor_center_y(ann["anchor"], page_h), reverse=True)


def build_comment_queue(
    comments: list[dict[str, Any]],
    page_h: float,
    text_w: float,
    font_name: str,
    font_size: float,
    marker_ids: dict[str, int],
) -> list[dict[str, Any]]:
    queue: list[dict[str, Any]] = []
    for ann in sort_comments_by_anchor(comments, page_h):
        marker_id = marker_ids.get(marker_key_for_anchor(ann["anchor"]), 0)
        label = f"[{marker_id}] " if marker_id > 0 else ""
        text_for_wrap = f"{label}{ann['text']}"
        lines = wrap_text_by_width(text_for_wrap, font_name, font_size, text_w)
        queue.append(
            {
                "anchor": ann["anchor"],
                "text": ann["text"],
                "lines": lines,
                "marker_id": marker_id,
                "continued": False,
                "anchor_y": comment_anchor_center_y(ann["anchor"], page_h),
            }
        )
    return queue


def place_comment_queue_on_page(
    queue: list[dict[str, Any]],
    page_h: float,
    box_x: float,
    box_w: float,
    font_name: str,
    font_size: float,
    anchor_mode: bool,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    ascent, descent, glyph_h, line_step = get_font_metrics(font_name, font_size)
    top_limit = page_h - COMMENT_MARGIN_PAD_Y
    bottom_limit = COMMENT_MARGIN_PAD_Y
    cursor_top = top_limit
    placements: list[dict[str, Any]] = []
    pending = [dict(item) for item in queue]

    while pending:
        item = pending[0]
        lines = list(item.get("lines") or [])
        if not lines:
            pending.pop(0)
            continue

        min_box_h = 2.0 * COMMENT_BOX_PAD_Y + glyph_h
        if cursor_top - bottom_limit < min_box_h:
            break

        full_box_h = 2.0 * COMMENT_BOX_PAD_Y + glyph_h + line_step * (len(lines) - 1)
        if anchor_mode and not item.get("continued", False):
            target_y = float(item.get("anchor_y") or (cursor_top - (full_box_h / 2.0))) - (full_box_h / 2.0)
        else:
            target_y = cursor_top - full_box_h

        max_box_y = cursor_top - full_box_h
        box_y = min(target_y, max_box_y)

        if box_y < bottom_limit:
            usable_h = cursor_top - bottom_limit - (2.0 * COMMENT_BOX_PAD_Y)
            if usable_h < glyph_h:
                break
            max_lines = int((usable_h - glyph_h) // line_step) + 1
            if max_lines <= 0:
                break
            take = min(max_lines, len(lines))
            part_lines = lines[:take]
            rest_lines = lines[take:]
            part_box_h = 2.0 * COMMENT_BOX_PAD_Y + glyph_h + line_step * (len(part_lines) - 1)
            part_y = max(bottom_limit, cursor_top - part_box_h)

            placements.append(
                {
                    "anchor": item["anchor"],
                    "lines": part_lines,
                    "marker_id": item.get("marker_id", 0),
                    "box_x": box_x,
                    "box_y": part_y,
                    "box_w": box_w,
                    "box_h": part_box_h,
                    "font_size": font_size,
                    "ascent": ascent,
                    "descent": descent,
                    "line_step": line_step,
                    "continued": bool(item.get("continued", False) or bool(rest_lines)),
                }
            )
            pending.pop(0)
            if rest_lines:
                remained = dict(item)
                remained["lines"] = rest_lines
                remained["continued"] = True
                remained["anchor_y"] = None
                pending.insert(0, remained)
            cursor_top = part_y - COMMENT_BOX_GAP
            continue

        placements.append(
            {
                "anchor": item["anchor"],
                "lines": lines,
                "marker_id": item.get("marker_id", 0),
                "box_x": box_x,
                "box_y": box_y,
                "box_w": box_w,
                "box_h": full_box_h,
                "font_size": font_size,
                "ascent": ascent,
                "descent": descent,
                "line_step": line_step,
                "continued": bool(item.get("continued", False)),
            }
        )
        pending.pop(0)
        cursor_top = box_y - COMMENT_BOX_GAP

    return placements, pending


def build_comment_layout_pages(
    comments: list[dict[str, Any]],
    page_h: float,
    margin_w: float,
    font_name: str,
    marker_ids: dict[str, int],
) -> tuple[list[dict[str, Any]], float]:
    inner_w = margin_w - (2.0 * COMMENT_MARGIN_PAD_X)
    text_w = inner_w - (2.0 * COMMENT_BOX_PAD_X)
    box_x = COMMENT_MARGIN_PAD_X
    box_w = inner_w

    for size in iter_font_sizes(COMMENT_FONT_START, COMMENT_FONT_MIN, COMMENT_FONT_STEP):
        queue = build_comment_queue(comments, page_h, text_w, font_name, size, marker_ids)
        placements, remaining = place_comment_queue_on_page(queue, page_h, box_x, box_w, font_name, size, True)
        if not remaining:
            return ([{"placements": placements, "font_size": size, "continuation": False}], size)

    min_size = COMMENT_FONT_MIN
    queue = build_comment_queue(comments, page_h, text_w, font_name, min_size, marker_ids)
    layouts: list[dict[str, Any]] = []

    first_placements, queue = place_comment_queue_on_page(queue, page_h, box_x, box_w, font_name, min_size, True)
    layouts.append({"placements": first_placements, "font_size": min_size, "continuation": False})

    while queue:
        placements, next_queue = place_comment_queue_on_page(queue, page_h, box_x, box_w, font_name, min_size, False)
        if not placements:
            # 1行も配置できないケースは強制的に先頭1行ずつ分割して進める
            item = dict(queue[0])
            lines = list(item.get("lines") or [])
            if not lines:
                queue = queue[1:]
                continue
            item["lines"] = [lines[0]]
            queue[0] = item
            if len(lines) > 1:
                rest = dict(item)
                rest["lines"] = lines[1:]
                rest["continued"] = True
                rest["anchor_y"] = None
                queue.insert(1, rest)
            continue
        layouts.append({"placements": placements, "font_size": min_size, "continuation": True})
        queue = next_queue

    return layouts, min_size


def draw_insertion_number_marker(
    c: canvas.Canvas,
    base_w: float,
    page_h: float,
    anchor: dict[str, Any],
    marker_id: int,
    font_name: str,
) -> None:
    _, y0, x1, y1 = bbox_to_pdf_coords(page_h, anchor["bbox"])
    ay = (y0 + y1) / 2.0
    start_x = min(base_w - 4.0, x1 + 1.0)
    label = str(marker_id)
    number_size = 5.1
    tw = pdfmetrics.stringWidth(label, font_name, number_size)
    badge_r = max(3.6, (tw / 2.0) + 1.3)
    badge_cx = min(base_w + 11.0, start_x + badge_r + 1.6)
    badge_cy = ay

    c.setStrokeColor(Color(0.08, 0.24, 0.80, alpha=0.90))
    c.setLineWidth(0.7)
    c.line(start_x, ay, badge_cx - badge_r, ay)

    c.setFillColor(Color(0.08, 0.24, 0.80, alpha=0.90))
    c.circle(badge_cx, badge_cy, badge_r, stroke=1, fill=1)

    c.setFillColor(Color(1.0, 1.0, 1.0, alpha=1.0))
    c.setFont(font_name, number_size)
    c.drawString(badge_cx - (tw / 2.0), badge_cy - (number_size * 0.36), label)


def build_comment_overlay_page(
    width: float,
    height: float,
    base_w: float,
    strike_entries: list[dict[str, Any]],
    layout: dict[str, Any],
    regular_font: str,
    bold_font: str,
    marker_ids: dict[str, int],
    draw_markers: bool,
    continuation_label: str | None,
) -> Any:
    buf = BytesIO()
    c = canvas.Canvas(buf, pagesize=(width, height))

    for entry in strike_entries:
        x0, y0, x1, y1 = bbox_to_pdf_coords(height, entry["bbox"])
        y = (y0 + y1) / 2.0
        c.setStrokeColor(Color(0.86, 0.10, 0.10, alpha=0.9))
        c.setLineWidth(1.2)
        c.line(x0, y, x1, y)

    c.setStrokeColor(Color(0.80, 0.80, 0.80, alpha=0.9))
    c.setLineWidth(0.6)
    c.line(base_w, 0.0, base_w, height)

    if continuation_label:
        c.setFillColor(Color(0.25, 0.25, 0.25, alpha=0.95))
        c.setFont(regular_font, 7)
        c.drawString(base_w + COMMENT_MARGIN_PAD_X, height - 12.0, continuation_label)

    marker_seen: set[str] = set()
    for placement in layout.get("placements", []):
        anchor = placement["anchor"]
        marker_key = marker_key_for_anchor(anchor)
        marker_id = marker_ids.get(marker_key, 0)

        if draw_markers and marker_key not in marker_seen:
            marker_seen.add(marker_key)
            marker_id > 0 and draw_insertion_number_marker(c, base_w, height, anchor, marker_id, regular_font)

        box_x = base_w + float(placement["box_x"])
        box_y = float(placement["box_y"])
        box_w = float(placement["box_w"])
        box_h = float(placement["box_h"])
        font_size = float(placement["font_size"])
        ascent = float(placement.get("ascent", get_font_metrics(regular_font, font_size)[0]))
        line_step = float(placement.get("line_step", get_font_metrics(regular_font, font_size)[3]))

        c.setStrokeColor(Color(0.10, 0.20, 0.80, alpha=0.85))
        c.setFillColor(Color(1.0, 1.0, 1.0, alpha=0.90))
        c.setLineWidth(0.6)
        c.rect(box_x, box_y, box_w, box_h, stroke=1, fill=1)

        lines = list(placement["lines"])
        clip_x = box_x + 0.3
        clip_y = box_y + 0.3
        clip_w = max(0.2, box_w - 0.6)
        clip_h = max(0.2, box_h - 0.6)
        c.saveState()
        clip_path = c.beginPath()
        clip_path.rect(clip_x, clip_y, clip_w, clip_h)
        c.clipPath(clip_path, stroke=0, fill=0)
        c.setFillColor(Color(0.05, 0.05, 0.05, alpha=1.0))
        y_cursor = box_y + box_h - COMMENT_BOX_PAD_Y - ascent
        for line in lines:
            draw_text(c, box_x + COMMENT_BOX_PAD_X, y_cursor, line, regular_font, font_size)
            y_cursor -= line_step
        c.restoreState()

    c.showPage()
    c.save()
    buf.seek(0)
    return PdfReader(buf).pages[0]


def merge_comment_overlay_with_margin(
    base_pdf: Path,
    out_pdf: Path,
    draw_plan: dict[int, dict[str, Any]],
    regular_font: str,
    bold_font: str,
    stats: dict[str, Any],
) -> None:
    base_reader = PdfReader(str(base_pdf))
    writer = PdfWriter()

    min_font_used: float | None = None
    continuation_pages = 0

    for i, base_page in enumerate(base_reader.pages):
        page_num = i + 1
        base_w = float(base_page.mediabox.width)
        base_h = float(base_page.mediabox.height)
        full_w = base_w + COMMENT_MARGIN_WIDTH

        page_plan = draw_plan.get(page_num, {"strike": [], "comment": []})
        comments = page_plan.get("comment", [])
        marker_ids: dict[str, int] = {}
        next_marker_id = 1
        for ann in sort_comments_by_anchor(comments, base_h):
            key = marker_key_for_anchor(ann["anchor"])
            if key in marker_ids:
                continue
            marker_ids[key] = next_marker_id
            next_marker_id += 1

        layouts, page_min_font = build_comment_layout_pages(
            comments,
            base_h,
            COMMENT_MARGIN_WIDTH,
            regular_font,
            marker_ids,
        )

        if min_font_used is None:
            min_font_used = page_min_font
        else:
            min_font_used = min(min_font_used, page_min_font)

        out_page = writer.add_blank_page(width=full_w, height=base_h)
        out_page.merge_page(base_page)
        main_overlay = build_comment_overlay_page(
            full_w,
            base_h,
            base_w,
            page_plan.get("strike", []),
            layouts[0],
            regular_font,
            bold_font,
            marker_ids,
            True,
            None,
        )
        out_page.merge_page(main_overlay)

        for cont_idx, layout in enumerate(layouts[1:], start=1):
            continuation_pages += 1
            cont_page = writer.add_blank_page(width=full_w, height=base_h)
            label = f"page {page_num} comments (continued {cont_idx})"
            cont_overlay = build_comment_overlay_page(
                full_w,
                base_h,
                base_w,
                [],
                layout,
                regular_font,
                bold_font,
                marker_ids,
                False,
                label,
            )
            cont_page.merge_page(cont_overlay)

    with out_pdf.open("wb") as f:
        writer.write(f)

    stats["comment_pages_extended"] = len(base_reader.pages)
    stats["comment_min_font_used"] = float(min_font_used if min_font_used is not None else COMMENT_FONT_START)
    stats["comment_continuation_pages"] = continuation_pages


def annotate(args: argparse.Namespace) -> dict[str, Any]:
    payload = json.loads(Path(args.input_json).read_text(encoding="utf-8"))

    map_a = payload.get("map_a", [])
    map_b = payload.get("map_b", [])
    deleted_ranges = payload.get("deleted_ranges", [])
    added_ranges = payload.get("added_ranges", [])
    ops = payload.get("ops", [])

    stats: dict[str, Any] = {
        "skipped_duplicates": 0,
        "map_a_missing": 0,
        "map_b_missing": 0,
        "comment_merged_groups": 0,
    }

    deleted_indices = range_to_indices(deleted_ranges)
    added_indices = range_to_indices(added_ranges)

    deleted_entries = map_entries_for_indices(map_a, deleted_indices, stats, "map_a_missing")
    added_entries = map_entries_for_indices(map_b, added_indices, stats, "map_b_missing")

    deleted_entries = dedupe_draw_entries(deleted_entries, "deleted", stats)
    added_entries = dedupe_draw_entries(added_entries, "added", stats)

    comments = build_comment_annotations(ops, map_a, map_b, stats)

    regular_font, bold_font = ensure_fonts()

    ann_a_plan: dict[int, dict[str, Any]] = defaultdict(lambda: {"strike": [], "mark": [], "comment": []})
    ann_b_plan: dict[int, dict[str, Any]] = defaultdict(lambda: {"strike": [], "mark": [], "comment": []})
    ann_comment_plan: dict[int, dict[str, Any]] = defaultdict(lambda: {"strike": [], "mark": [], "comment": []})

    for e in deleted_entries:
        page = int(e.get("page") or 0)
        ann_a_plan[page]["strike"].append(e)
        ann_comment_plan[page]["strike"].append(e)

    for e in added_entries:
        page = int(e.get("page") or 0)
        ann_b_plan[page]["mark"].append(e)

    for ann in comments:
        page = int(ann["anchor"].get("page") or 0)
        ann_comment_plan[page]["comment"].append(ann)

    merge_overlay(Path(args.source_a), Path(args.output_ann_a), ann_a_plan, regular_font, bold_font)
    merge_overlay(Path(args.source_b), Path(args.output_ann_b), ann_b_plan, regular_font, bold_font)
    merge_comment_overlay_with_margin(
        Path(args.source_a),
        Path(args.output_ann_comment),
        ann_comment_plan,
        regular_font,
        bold_font,
        stats,
    )

    stats["input_deleted_tokens"] = len(deleted_indices)
    stats["input_added_tokens"] = len(added_indices)
    stats["unique_deleted_draw_units"] = len(deleted_entries)
    stats["unique_added_draw_units"] = len(added_entries)
    stats["comment_count"] = len(comments)
    return stats


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--phase", choices=["reconstruct", "annotate"], required=True)

    p.add_argument("--input-xhtml")
    p.add_argument("--output-json")

    p.add_argument("--source-a")
    p.add_argument("--source-b")
    p.add_argument("--input-json")
    p.add_argument("--output-ann-a")
    p.add_argument("--output-ann-b")
    p.add_argument("--output-ann-comment")
    p.add_argument("--summary-json")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    if args.phase == "reconstruct":
        if not args.input_xhtml or not args.output_json:
            print("missing args for reconstruct", file=sys.stderr)
            return 2
        payload = reconstruct_from_xhtml(Path(args.input_xhtml))
        Path(args.output_json).write_text(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        return 0

    if args.phase == "annotate":
        required = [
            args.source_a,
            args.source_b,
            args.input_json,
            args.output_ann_a,
            args.output_ann_b,
            args.output_ann_comment,
            args.summary_json,
        ]
        if any(x is None for x in required):
            print("missing args for annotate", file=sys.stderr)
            return 2
        summary = annotate(args)
        Path(args.summary_json).write_text(
            json.dumps(summary, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
