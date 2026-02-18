#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import json
import math
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
        x_keys = ("xmin", "ymin", "xmax", "ymax")
        if all(k in self.word_attrs for k in x_keys):
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


def map_entries_for_indices(token_map: list[Any], indices: list[int], stats: dict[str, int], missing_key: str) -> list[dict[str, Any]]:
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


def wrap_text(text: str, max_chars: int = 18) -> list[str]:
    if not text:
        return [""]
    lines: list[str] = []
    cur = ""
    for ch in text:
        cur += ch
        if len(cur) >= max_chars:
            lines.append(cur)
            cur = ""
    if cur:
        lines.append(cur)
    return lines


def draw_bold_text(c: canvas.Canvas, x: float, y: float, text: str, font: str, size: int) -> None:
    c.setFont(font, size)
    c.drawString(x, y, text)
    c.drawString(x + 0.25, y, text)


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
        tokens: list[str] = []
        for i in range(b_start, b_end + 1):
            if 0 <= i < len(map_b):
                item = map_b[i]
                if item and item.get("token"):
                    t = str(item["token"])
                    if t == "<$>":
                        continue
                    tokens.append(html.unescape(t))
        text = "".join(tokens).strip()
        if not text:
            continue
        anchor = nearest_anchor(op)
        if not anchor:
            stats["map_a_missing"] = stats.get("map_a_missing", 0) + 1
            continue
        annotations.append({"anchor": anchor, "text": text})

    uniq: list[dict[str, Any]] = []
    seen: set[str] = set()
    for ann in annotations:
        anchor = ann["anchor"]
        page = int(anchor.get("page") or 0)
        word_seq = anchor.get("word_seq")
        key = f"comment:{page}:{word_seq}:{ann['text']}"
        if key in seen:
            stats["skipped_duplicates"] = stats.get("skipped_duplicates", 0) + 1
            continue
        seen.add(key)
        uniq.append(ann)
    return uniq


def merge_overlay(
    base_pdf: Path,
    out_pdf: Path,
    draw_plan: dict[int, dict[str, Any]],
    regular_font: str,
    bold_font: str,
) -> None:
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

        for ann in plan.get("comment", []):
            anchor = ann["anchor"]
            text = ann["text"]
            x0, y0, x1, y1 = bbox_to_pdf_coords(h, anchor["bbox"])
            ax = min(w - 8, x1 + 2)
            ay = min(h - 8, max(8, (y0 + y1) / 2.0))
            box_x = min(w - 160, ax + 14)
            lines = wrap_text(text, 16)
            box_h = 8 + len(lines) * 11
            box_y = min(h - box_h - 6, max(6, ay - box_h / 2.0))

            c.setStrokeColor(Color(0.10, 0.20, 0.80, alpha=0.95))
            c.setLineWidth(1.0)
            c.line(ax, ay, box_x, box_y + box_h - 6)
            c.circle(ax, ay, 1.3, stroke=1, fill=1)

            c.setStrokeColor(Color(0.10, 0.20, 0.80, alpha=0.95))
            c.setFillColor(Color(1.0, 1.0, 0.80, alpha=0.95))
            c.rect(box_x, box_y, 150, box_h, stroke=1, fill=1)

            c.setFillColor(Color(0.05, 0.05, 0.05, alpha=1.0))
            y_cursor = box_y + box_h - 13
            for line in lines:
                draw_bold_text(c, box_x + 4, y_cursor, line, bold_font, 9)
                y_cursor -= 11

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


def annotate(args: argparse.Namespace) -> dict[str, Any]:
    payload = json.loads(Path(args.input_json).read_text(encoding="utf-8"))

    map_a = payload.get("map_a", [])
    map_b = payload.get("map_b", [])
    deleted_ranges = payload.get("deleted_ranges", [])
    added_ranges = payload.get("added_ranges", [])
    ops = payload.get("ops", [])

    stats: dict[str, int] = {
        "skipped_duplicates": 0,
        "map_a_missing": 0,
        "map_b_missing": 0,
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
    merge_overlay(Path(args.source_a), Path(args.output_ann_comment), ann_comment_plan, regular_font, bold_font)

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
