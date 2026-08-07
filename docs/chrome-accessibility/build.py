#!/usr/bin/env python3
"""Build the Chrome accessibility slide deck.

Reads the per-module Markdown sources in `slides/` and emits a single
self-contained `index.html` that works offline, prints to PDF, and stays
usable with JavaScript disabled (the deck degrades to a linear document).

    ./build.py            # write index.html next to this script
    ./build.py --check    # parse and validate only, write nothing

Slide source format (see slides/README-format.md):

    ---
    module: The accessibility tree
    part: Part II - The web platform
    ---

    ## Slide title
    Paragraph text.
    - a bullet
      - a nested bullet
    KEY: the one thing to remember
    TRY: a hands-on exercise
    REF: file or URL worth opening
    NOTE: speaker note, not shown on the slide by default

    ```cpp
    struct AXNodeData { ... };
    ```
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
SLIDE_DIR = HERE / "slides"
OUT = HERE / "index.html"

EXPECTED_SLIDES = 300


# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------


@dataclass
class Slide:
    title: str
    blocks: list = field(default_factory=list)  # list of (kind, payload)
    notes: list = field(default_factory=list)
    module: str = ""
    part: str = ""
    number: int = 0
    module_index: int = 0
    source: str = ""


@dataclass
class Module:
    name: str
    part: str
    slug: str
    slides: list = field(default_factory=list)
    source: str = ""


FRONT_MATTER = re.compile(r"\A---\n(.*?)\n---\n", re.S)


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug or "section"


def parse_module(path: Path) -> Module:
    raw = path.read_text(encoding="utf-8")
    match = FRONT_MATTER.match(raw)
    if not match:
        raise SystemExit(f"{path.name}: missing '---' front matter block")
    meta = {}
    for line in match.group(1).splitlines():
        if not line.strip():
            continue
        if ":" not in line:
            raise SystemExit(f"{path.name}: bad front matter line: {line!r}")
        key, value = line.split(":", 1)
        meta[key.strip()] = value.strip()
    for required in ("module", "part"):
        if required not in meta:
            raise SystemExit(f"{path.name}: front matter needs a '{required}' key")

    module = Module(
        name=meta["module"],
        part=meta["part"],
        slug=meta.get("slug") or slugify(meta["module"]),
        source=path.name,
    )

    body = raw[match.end() :]
    chunks = re.split(r"^## ", body, flags=re.M)
    if chunks and chunks[0].strip():
        raise SystemExit(f"{path.name}: content before the first '## ' slide title")
    for chunk in chunks[1:]:
        title, _, rest = chunk.partition("\n")
        slide = Slide(
            title=title.strip(),
            module=module.name,
            part=module.part,
            source=path.name,
        )
        parse_body(rest, slide, path)
        module.slides.append(slide)
    if not module.slides:
        raise SystemExit(f"{path.name}: no slides found")
    return module


LIST_ITEM = re.compile(r"^(\s*)[-*] +(.*)$")
ORDERED_ITEM = re.compile(r"^(\s*)\d+\. +(.*)$")
CALLOUTS = {"KEY": "key", "TRY": "try", "REF": "ref", "WHY": "why", "WATCH": "watch"}


def parse_body(text: str, slide: Slide, path: Path) -> None:
    lines = text.split("\n")
    i = 0
    n = len(lines)
    para: list[str] = []

    def flush_para() -> None:
        nonlocal para
        if para:
            slide.blocks.append(("p", " ".join(para).strip()))
            para = []

    while i < n:
        line = lines[i]
        stripped = line.strip()

        if not stripped:
            flush_para()
            i += 1
            continue

        if stripped.startswith("```"):
            flush_para()
            info = stripped[3:].strip() or "text"
            lang, _, caption = info.partition(" ")
            i += 1
            code: list[str] = []
            while i < n and not lines[i].strip().startswith("```"):
                code.append(lines[i])
                i += 1
            if i >= n:
                raise SystemExit(f"{path.name}: unterminated code fence in {slide.title!r}")
            i += 1
            payload = "\n".join(code).rstrip()
            if lang == "svg":
                if not caption:
                    raise SystemExit(
                        f"{path.name}: the svg block in {slide.title!r} needs a caption "
                        "(```svg Some description) - it becomes the text alternative"
                    )
                slide.blocks.append(("svg", (caption.strip(), payload)))
            else:
                slide.blocks.append(("code", (lang, payload)))
            continue

        callout = re.match(r"^(KEY|TRY|REF|WHY|WATCH): +(.*)$", stripped)
        if callout:
            flush_para()
            kind, body = callout.group(1), callout.group(2)
            extra = []
            i += 1
            while i < n and lines[i].startswith("    ") and lines[i].strip():
                extra.append(lines[i].strip())
                i += 1
            slide.blocks.append(("callout", (CALLOUTS[kind], " ".join([body] + extra))))
            continue

        if stripped.startswith("NOTE: "):
            flush_para()
            note = [stripped[len("NOTE: ") :]]
            i += 1
            while i < n and lines[i].startswith("    ") and lines[i].strip():
                note.append(lines[i].strip())
                i += 1
            slide.notes.append(" ".join(note))
            continue

        if line.lstrip().startswith("|") and line.rstrip().endswith("|"):
            flush_para()
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-{2,}:?", c) for c in cells):
                    rows.append(cells)
                i += 1
            slide.blocks.append(("table", rows))
            continue

        if LIST_ITEM.match(line) or ORDERED_ITEM.match(line):
            flush_para()
            items = []  # (depth, text, ordered)
            while i < n:
                m = LIST_ITEM.match(lines[i])
                mo = ORDERED_ITEM.match(lines[i])
                if m:
                    items.append((len(m.group(1)) // 2, m.group(2).strip(), False))
                elif mo:
                    items.append((len(mo.group(1)) // 2, mo.group(2).strip(), True))
                elif lines[i].startswith("  ") and lines[i].strip() and items:
                    # A wrapped continuation line for the previous item.
                    depth, txt, ordered = items[-1]
                    items[-1] = (depth, txt + " " + lines[i].strip(), ordered)
                else:
                    break
                i += 1
            slide.blocks.append(("list", items))
            continue

        para.append(stripped)
        i += 1

    flush_para()


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

KEYWORDS = {
    "cpp": """alignas auto bool break case char class const constexpr continue default delete
        do double else enum explicit export extern false float for friend if inline int long
        mutable namespace new noexcept nullptr operator override private protected public
        return short signed sizeof static struct switch template this throw true try typedef
        typename union unsigned using virtual void volatile while int32_t uint32_t int64_t
        size_t std""".split(),
    "js": """async await break case catch class const continue default delete do else export
        extends false finally for from function if import in instanceof let new null of return
        static super switch this throw true try typeof undefined var void while yield""".split(),
    "py": """and as assert async await break class continue def del elif else except False
        finally for from global if import in is lambda None not or pass raise return True try
        while with yield""".split(),
    "sh": """autoninja cd echo export fi for gn if in ninja out python3 then while""".split(),
}
KEYWORDS["python"] = KEYWORDS["py"]
KEYWORDS["c++"] = KEYWORDS["cpp"]
KEYWORDS["shell"] = KEYWORDS["sh"]
KEYWORDS["bash"] = KEYWORDS["sh"]
KEYWORDS["ts"] = KEYWORDS["js"]

# Operates on already-escaped text; `&amp;`-style entities are matched as atoms
# so a span never lands in the middle of one.
TOKEN = re.compile(
    r"(?P<entity>&[a-zA-Z]+;|&#\d+;)"
    r"|(?P<comment>//[^\n]*|#[^\n]*|/\*.*?\*/)"
    r"|(?P<string>\"(?:[^\"\\\n]|\\.)*\"|'(?:[^'\\\n]|\\.)*')"
    r"|(?P<number>\b\d[\d.a-fx]*\b)"
    r"|(?P<word>[A-Za-z_][A-Za-z0-9_:]*)",
    re.S,
)

INLINE_CODE = re.compile(r"`([^`]+)`")
BOLD = re.compile(r"\*\*([^*]+)\*\*")
ITALIC = re.compile(r"(?<![*\w])\*([^*\n]+)\*(?!\*)")
LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def inline(text: str) -> str:
    """Escape then apply the small inline Markdown subset."""
    placeholders: list[str] = []

    def stash(markup: str) -> str:
        placeholders.append(markup)
        return f"\x00{len(placeholders) - 1}\x00"

    def code_repl(m):
        return stash("<code>" + html.escape(m.group(1)) + "</code>")

    text = INLINE_CODE.sub(code_repl, text)

    def link_repl(m):
        label, href = m.group(1), m.group(2)
        safe = html.escape(href, quote=True)
        if not re.match(r"^(https?:|mailto:|#|chrome://|about:)", href):
            return stash("<span class='ref'>" + html.escape(label) + "</span>")
        return stash(
            f"<a href='{safe}' rel='noreferrer noopener'>{html.escape(label)}</a>"
        )

    text = LINK.sub(link_repl, text)
    text = html.escape(text)
    text = BOLD.sub(r"<strong>\1</strong>", text)
    text = ITALIC.sub(r"<em>\1</em>", text)

    def restore(m):
        return placeholders[int(m.group(1))]

    return re.sub(r"\x00(\d+)\x00", restore, text)


def highlight(code: str, lang: str) -> str:
    escaped = html.escape(code)
    keywords = set(KEYWORDS.get(lang.lower(), ()))
    if lang.lower() in ("html", "text", "tree", "txt", ""):
        # Tree dumps and HTML read better without keyword coloring; still tag
        # strings and comments for orientation.
        keywords = set()

    def repl(m):
        kind = m.lastgroup
        value = m.group()
        if kind == "entity":
            return value
        if kind == "comment":
            return f"<span class='c-com'>{value}</span>"
        if kind == "string":
            return f"<span class='c-str'>{value}</span>"
        if kind == "number":
            return f"<span class='c-num'>{value}</span>"
        if kind == "word":
            if value in keywords:
                return f"<span class='c-kw'>{value}</span>"
            if re.match(r"^(ax|AX|k[A-Z]|blink|ui|content|chrome)", value):
                return f"<span class='c-id'>{value}</span>"
        return value

    return TOKEN.sub(repl, escaped)


def render_blocks(slide: Slide) -> str:
    out: list[str] = []
    for kind, payload in slide.blocks:
        if kind == "p":
            out.append(f"<p>{inline(payload)}</p>")
        elif kind == "code":
            lang, code = payload
            out.append(
                f"<pre class='code' data-lang='{html.escape(lang)}' tabindex='0'>"
                f"<code>{highlight(code, lang)}</code></pre>"
            )
        elif kind == "svg":
            caption, markup = payload
            label = html.escape(caption, quote=True)
            # The diagram is the content, so it needs a text alternative; the
            # caption is both the accessible name and the visible figcaption.
            markup = re.sub(
                r"<svg\b",
                f"<svg role='img' aria-label='{label}'",
                markup,
                count=1,
            )
            out.append(
                f"<figure class='diagram'>{markup}"
                f"<figcaption>{inline(caption)}</figcaption></figure>"
            )
        elif kind == "callout":
            variant, body = payload
            label = {
                "key": "Key idea",
                "try": "Try it",
                "ref": "Where to look",
                "why": "Why it is like this",
                "watch": "Watch out",
            }[variant]
            out.append(
                f"<aside class='callout {variant}'>"
                f"<span class='callout-label'>{label}</span>"
                f"<span class='callout-body'>{inline(body)}</span></aside>"
            )
        elif kind == "table":
            if not payload:
                continue
            head, *rest = payload
            cells = "".join(f"<th scope='col'>{inline(c)}</th>" for c in head)
            rows = "".join(
                "<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>"
                for r in rest
            )
            out.append(
                f"<div class='table-wrap'><table><thead><tr>{cells}</tr></thead>"
                f"<tbody>{rows}</tbody></table></div>"
            )
        elif kind == "list":
            out.append(render_list(payload))
    return "".join(out)


def render_list(items) -> str:
    html_out: list[str] = []
    stack: list[int] = []

    def open_list(ordered: bool) -> str:
        return "<ol>" if ordered else "<ul>"

    def close_list() -> str:
        return "</ol>" if stack_ordered.pop() else "</ul>"

    stack_ordered: list[bool] = []
    prev_depth = -1
    for depth, text, ordered in items:
        depth = min(depth, prev_depth + 1)
        while prev_depth > depth:
            html_out.append("</li>")
            html_out.append(close_list())
            prev_depth -= 1
        if prev_depth == depth:
            html_out.append("</li>")
        else:
            html_out.append(open_list(ordered))
            stack_ordered.append(ordered)
            prev_depth = depth
        html_out.append(f"<li>{inline(text)}")
    while prev_depth >= 0:
        html_out.append("</li>")
        html_out.append(close_list())
        prev_depth -= 1
    return "".join(html_out)


def render_slide(slide: Slide, total: int) -> str:
    notes = ""
    if slide.notes:
        items = "".join(f"<p>{inline(n)}</p>" for n in slide.notes)
        notes = f"<div class='notes'><h3>Speaker notes</h3>{items}</div>"
    return (
        f"<section class='slide' id='slide-{slide.number}' "
        f"data-n='{slide.number}' data-module='{html.escape(slide.module)}' "
        f"aria-labelledby='slide-{slide.number}-title' tabindex='-1'>"
        f"<div class='slide-inner'>"
        f"<p class='eyebrow'><span class='part'>{html.escape(slide.part)}</span>"
        f"<span class='sep' aria-hidden='true'>/</span>"
        f"<span class='mod'>{html.escape(slide.module)}</span></p>"
        f"<h2 id='slide-{slide.number}-title'>{inline(slide.title)}</h2>"
        f"<div class='body'>{render_blocks(slide)}</div>"
        f"{notes}"
        f"<p class='pagenum' aria-hidden='true'>{slide.number} / {total}</p>"
        f"</div></section>"
    )


# --------------------------------------------------------------------------
# Page template
# --------------------------------------------------------------------------

CSS = """
*,*::before,*::after{box-sizing:border-box}
:root{
  color-scheme:light dark;
  --bg:#f6f7f9; --panel:#ffffff; --ink:#161a1f; --muted:#525c66;
  --line:#d9dee5; --accent:#1a56b8; --accent-soft:#e7eefb;
  --key:#0b6b53; --key-soft:#e2f4ee; --try:#8a4b00; --try-soft:#fdf0df;
  --ref:#4b3aa8; --ref-soft:#eeebfc; --why:#1f5f7a; --why-soft:#e4f2f8;
  --watch:#a3232a; --watch-soft:#fbe9ea;
  --code-bg:#f2f4f7; --code-ink:#1d2733;
  --c-kw:#8b1a8b; --c-str:#0a6b3d; --c-com:#6a737d; --c-num:#9a4b00; --c-id:#124a9c;
  --shadow:0 1px 2px rgba(16,24,40,.06),0 8px 24px rgba(16,24,40,.06);
  --slide-max:70rem;
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    --bg:#0e1116; --panel:#151a21; --ink:#e6eaf0; --muted:#9aa6b4;
    --line:#28313c; --accent:#7aa7f0; --accent-soft:#17233a;
    --key:#5fd6b0; --key-soft:#0f2a24; --try:#f0b878; --try-soft:#2b1f10;
    --ref:#b3a6f5; --ref-soft:#1e1a33; --why:#7fc7e8; --why-soft:#0f2530;
    --watch:#f19aa0; --watch-soft:#2e1417;
    --code-bg:#0b0f14; --code-ink:#dbe4ef;
    --c-kw:#e29bf0; --c-str:#7ddba4; --c-com:#7f8b99; --c-num:#f0b878; --c-id:#8fc0ff;
    --shadow:0 1px 2px rgba(0,0,0,.4),0 10px 30px rgba(0,0,0,.35);
  }
}
:root[data-theme="dark"]{
  --bg:#0e1116; --panel:#151a21; --ink:#e6eaf0; --muted:#9aa6b4;
  --line:#28313c; --accent:#7aa7f0; --accent-soft:#17233a;
  --key:#5fd6b0; --key-soft:#0f2a24; --try:#f0b878; --try-soft:#2b1f10;
  --ref:#b3a6f5; --ref-soft:#1e1a33; --why:#7fc7e8; --why-soft:#0f2530;
  --watch:#f19aa0; --watch-soft:#2e1417;
  --code-bg:#0b0f14; --code-ink:#dbe4ef;
  --c-kw:#e29bf0; --c-str:#7ddba4; --c-com:#7f8b99; --c-num:#f0b878; --c-id:#8fc0ff;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 10px 30px rgba(0,0,0,.35);
}
html,body{margin:0;padding:0}
body{
  background:var(--bg); color:var(--ink);
  font:16px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;
  -webkit-text-size-adjust:100%;
}
a{color:var(--accent)}
a:focus-visible,button:focus-visible,[tabindex]:focus-visible,input:focus-visible{
  outline:3px solid var(--accent); outline-offset:2px; border-radius:4px;
}
/* the slide itself takes focus on navigation: show it, but quietly */
.slide:focus-visible{outline:2px solid var(--accent);outline-offset:-8px}
.skip{position:absolute;left:-9999px;top:0;background:var(--panel);color:var(--ink);
  padding:.6rem 1rem;z-index:60;border:1px solid var(--line);border-radius:0 0 8px 0}
.skip:focus{left:0}
.visually-hidden{position:absolute!important;width:1px;height:1px;margin:-1px;padding:0;
  overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;border:0}

/* ---------- chrome ---------- */
.topbar{position:sticky;top:0;z-index:40;display:flex;gap:.5rem;align-items:center;
  padding:.5rem .75rem;background:var(--panel);border-bottom:1px solid var(--line)}
.topbar h1{font-size:.95rem;margin:0 auto 0 0;font-weight:650;letter-spacing:-.01em;
  white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.topbar h1 .sub{color:var(--muted);font-weight:400}
.btn{font:inherit;font-size:.85rem;line-height:1;padding:.5rem .7rem;border-radius:8px;
  border:1px solid var(--line);background:var(--panel);color:var(--ink);cursor:pointer}
.btn:hover{background:var(--accent-soft);border-color:var(--accent)}
.btn[aria-pressed="true"]{background:var(--accent-soft);border-color:var(--accent)}
.counter{font-variant-numeric:tabular-nums;color:var(--muted);font-size:.85rem;
  padding:0 .35rem;white-space:nowrap}
.progress{height:3px;background:transparent}
.progress>div{height:100%;background:var(--accent);width:0}

/* ---------- deck ---------- */
main{display:block}
.slide{background:var(--panel);border:1px solid var(--line);border-radius:14px;
  margin:1rem auto;max-width:var(--slide-max);box-shadow:var(--shadow);scroll-margin-top:4rem}
.slide-inner{padding:clamp(1.1rem,3vw,2.4rem);min-height:0}
.eyebrow{margin:0 0 .5rem;font-size:.74rem;letter-spacing:.06em;text-transform:uppercase;
  color:var(--muted);display:flex;gap:.5rem;flex-wrap:wrap}
.eyebrow .sep{opacity:.5}
.slide h2{margin:0 0 .9rem;font-size:clamp(1.35rem,2.6vw,2rem);line-height:1.15;
  letter-spacing:-.02em;font-weight:680}
.body>*:first-child{margin-top:0}
.body p{margin:.6rem 0;max-width:62ch}
.body ul,.body ol{margin:.6rem 0;padding-left:1.35rem;max-width:70ch}
.body li{margin:.3rem 0}
.body li>ul,.body li>ol{margin:.25rem 0}
code{font-family:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,"Liberation Mono",monospace;
  font-size:.88em;background:var(--code-bg);padding:.1em .35em;border-radius:5px}
pre.code{background:var(--code-bg);color:var(--code-ink);padding:.85rem 1rem;border-radius:10px;
  overflow-x:auto;border:1px solid var(--line);margin:.8rem 0;font-size:.86rem;line-height:1.5}
pre.code code{background:none;padding:0;font-size:1em}
.c-kw{color:var(--c-kw)}.c-str{color:var(--c-str)}.c-com{color:var(--c-com);font-style:italic}
.c-num{color:var(--c-num)}.c-id{color:var(--c-id)}
.callout{display:flex;gap:.7rem;align-items:baseline;margin:.8rem 0;padding:.7rem .9rem;
  border-radius:10px;border:1px solid var(--line);background:var(--accent-soft);max-width:70ch}
.callout-label{font-size:.7rem;letter-spacing:.06em;text-transform:uppercase;font-weight:700;
  white-space:nowrap;color:var(--accent)}
.callout.key{background:var(--key-soft);border-color:var(--key)}
.callout.key .callout-label{color:var(--key)}
.callout.try{background:var(--try-soft);border-color:var(--try)}
.callout.try .callout-label{color:var(--try)}
.callout.ref{background:var(--ref-soft);border-color:var(--ref)}
.callout.ref .callout-label{color:var(--ref)}
.callout.why{background:var(--why-soft);border-color:var(--why)}
.callout.why .callout-label{color:var(--why)}
.callout.watch{background:var(--watch-soft);border-color:var(--watch)}
.callout.watch .callout-label{color:var(--watch)}
.ref{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:.88em}
.diagram{margin:.9rem 0;max-width:52rem}
.diagram svg{width:100%;height:auto;display:block;overflow:visible}
.diagram figcaption{margin-top:.4rem;font-size:.8rem;color:var(--muted)}
/* diagram vocabulary: boxes take the panel ground, labels the ink, flow the accent */
.d-box{fill:var(--panel);stroke:var(--line);stroke-width:1.5}
.d-box-accent{fill:var(--accent-soft);stroke:var(--accent);stroke-width:1.5}
.d-box-warn{fill:var(--watch-soft);stroke:var(--watch);stroke-width:1.5}
.d-box-key{fill:var(--key-soft);stroke:var(--key);stroke-width:1.5}
.d-zone{fill:none;stroke:var(--line);stroke-width:1;stroke-dasharray:5 4}
.d-t{fill:var(--ink);font:500 13px ui-sans-serif,system-ui,sans-serif}
.d-t-sm{fill:var(--muted);font:11px ui-sans-serif,system-ui,sans-serif}
.d-t-mono{fill:var(--ink);font:12px ui-monospace,Menlo,Consolas,monospace}
.d-line{stroke:var(--accent);stroke-width:1.8;fill:none}
.d-line-back{stroke:var(--muted);stroke-width:1.5;fill:none;stroke-dasharray:6 4}
.d-fill-accent{fill:var(--accent)}
.d-fill-muted{fill:var(--muted)}
.table-wrap{overflow-x:auto;margin:.8rem 0}
table{border-collapse:collapse;font-size:.9rem;min-width:min(100%,32rem)}
th,td{border:1px solid var(--line);padding:.4rem .6rem;text-align:left;vertical-align:top}
th{background:var(--accent-soft);font-weight:650}
.notes{margin-top:1rem;padding-top:.8rem;border-top:1px dashed var(--line);color:var(--muted);
  font-size:.9rem}
.notes h3{font-size:.72rem;letter-spacing:.06em;text-transform:uppercase;margin:0 0 .3rem}
.notes p{margin:.3rem 0;max-width:70ch}
.pagenum{position:absolute;right:1.1rem;bottom:.7rem;font-size:.75rem;color:var(--muted);
  font-variant-numeric:tabular-nums;margin:0}

/* ---------- presentation mode (JS on) ---------- */
.js .slide{display:none;position:relative;margin:1rem auto;min-height:calc(100vh - 6.5rem)}
.js .slide.current{display:block}
.js .slide-inner{display:flex;flex-direction:column;justify-content:center;min-height:calc(100vh - 8rem)}
.js .notes{display:none}
.js.show-notes .notes{display:block}
.js .slide.current{animation:fade .18s ease-out}
@keyframes fade{from{opacity:.35}to{opacity:1}}
@media (prefers-reduced-motion:reduce){.js .slide.current{animation:none}}
.nojs-hint{max-width:var(--slide-max);margin:1rem auto;padding:.6rem .9rem;color:var(--muted);
  font-size:.9rem}
.js .nojs-hint{display:none}

/* ---------- dialogs ---------- */
.overlay{position:fixed;inset:0;background:rgba(10,14,20,.55);z-index:50;display:none;
  padding:1rem;overflow:auto}
.overlay.open{display:block}
.panel{background:var(--panel);color:var(--ink);border:1px solid var(--line);border-radius:14px;
  max-width:64rem;margin:2rem auto;padding:1.2rem;box-shadow:var(--shadow)}
.panel h2{margin:.1rem 0 .8rem;font-size:1.15rem}
.panel .close{float:right}
#search-input{font:inherit;padding:.55rem .7rem;width:100%;border-radius:9px;
  border:1px solid var(--line);background:var(--bg);color:var(--ink)}
.results{list-style:none;margin:.8rem 0 0;padding:0;max-height:60vh;overflow:auto}
.results li{margin:0}
.results button{display:block;width:100%;text-align:left;background:none;border:0;color:inherit;
  font:inherit;padding:.5rem .6rem;border-radius:8px;cursor:pointer}
.results button:hover{background:var(--accent-soft)}
.results .rn{color:var(--muted);font-variant-numeric:tabular-nums;margin-right:.6rem}
.results .rm{color:var(--muted);font-size:.8rem;display:block}
.grid{display:grid;gap:.5rem;grid-template-columns:repeat(auto-fill,minmax(15rem,1fr));margin:.4rem 0 1.2rem}
.grid button{text-align:left;background:var(--bg);border:1px solid var(--line);border-radius:10px;
  padding:.5rem .6rem;font:inherit;font-size:.85rem;color:inherit;cursor:pointer}
.grid button:hover{border-color:var(--accent);background:var(--accent-soft)}
.grid .gn{color:var(--muted);font-variant-numeric:tabular-nums;font-size:.78rem}
.modhead{margin:1.1rem 0 .3rem;font-size:.95rem;display:flex;justify-content:space-between;
  gap:1rem;align-items:baseline;border-bottom:1px solid var(--line);padding-bottom:.25rem}
.modhead .cnt{color:var(--muted);font-size:.8rem;font-weight:400}
kbd{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:.8rem;border:1px solid var(--line);
  border-bottom-width:2px;border-radius:5px;padding:.05em .4em;background:var(--bg)}
.keys{list-style:none;padding:0;margin:0;display:grid;gap:.35rem;
  grid-template-columns:repeat(auto-fill,minmax(17rem,1fr))}

/* ---------- print ---------- */
@media print{
  .topbar,.overlay,.progress,.nojs-hint{display:none!important}
  body{background:#fff;color:#000;font-size:12px}
  .slide h2{font-size:1.5rem;margin-bottom:.5rem}
  .js .slide,.slide{display:block!important;page-break-after:always;break-after:page;
    box-shadow:none;border:0;min-height:0;margin:0;max-width:none}
  .js .slide-inner{min-height:0;display:block}
  .js .notes{display:block}
  .slide-inner{padding:1.2cm}
  pre.code{white-space:pre-wrap}
  @page{size:landscape;margin:1cm}
}
"""

JS = r"""
(function(){
  var root=document.documentElement;
  root.classList.add('js');
  var slides=Array.prototype.slice.call(document.querySelectorAll('.slide'));
  var total=slides.length;
  var live=document.getElementById('live');
  var counter=document.getElementById('counter');
  var bar=document.getElementById('bar');
  var idx=0;

  function clamp(n){return Math.max(0,Math.min(total-1,n));}

  function show(n,opts){
    opts=opts||{};
    n=clamp(n);
    if(slides[idx]) slides[idx].classList.remove('current');
    idx=n;
    var el=slides[idx];
    el.classList.add('current');
    counter.textContent=(idx+1)+' / '+total;
    bar.style.width=((idx+1)/total*100)+'%';
    if(!opts.silent){
      try{history.replaceState(null,'','#slide-'+(idx+1));}catch(e){location.hash='slide-'+(idx+1);}
    }
    try{localStorage.setItem('a11y-deck-slide',String(idx+1));}catch(e){}
    if(opts.focus!==false){el.focus({preventScroll:true});}
    window.scrollTo(0,0);
    var t=el.querySelector('h2');
    live.textContent='Slide '+(idx+1)+' of '+total+': '+(t?t.textContent:'');
  }

  function next(){show(idx+1);} function prev(){show(idx-1);}

  // ---- dialogs ----
  var lastFocus=null;
  function openDlg(id){
    var d=document.getElementById(id);
    lastFocus=document.activeElement;
    d.classList.add('open');
    // Prefer the text field over the close button, so '/' lands in search.
    var f=d.querySelector('input')||d.querySelector('button');
    if(f) f.focus();
  }
  function closeDlg(d){
    d.classList.remove('open');
    if(lastFocus&&lastFocus.focus) lastFocus.focus();
  }
  function closeAll(){
    Array.prototype.forEach.call(document.querySelectorAll('.overlay.open'),closeDlg);
  }
  document.addEventListener('click',function(e){
    var t=e.target;
    if(t.matches('.overlay')) closeDlg(t);
    var act=t.closest('[data-act]');
    if(!act) return;
    var a=act.getAttribute('data-act');
    if(a==='next') next();
    else if(a==='prev') prev();
    else if(a==='goto') show(parseInt(act.getAttribute('data-n'),10)-1);
    else if(a==='open') openDlg(act.getAttribute('data-target'));
    else if(a==='close') closeDlg(act.closest('.overlay'));
    else if(a==='notes') toggleNotes();
    else if(a==='theme') toggleTheme();
    if(a==='goto') closeAll();
  });

  // trap focus + escape inside open dialogs
  document.addEventListener('keydown',function(e){
    var open=document.querySelector('.overlay.open');
    if(open){
      if(e.key==='Escape'){e.preventDefault();closeDlg(open);return;}
      if(e.key==='Tab'){
        var f=open.querySelectorAll('button,input,[href],[tabindex]:not([tabindex="-1"])');
        if(!f.length) return;
        var first=f[0],last=f[f.length-1];
        if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}
        else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}
      }
      return;
    }
    if(e.target.tagName==='INPUT'||e.metaKey||e.ctrlKey||e.altKey) return;
    switch(e.key){
      case 'ArrowRight': case 'PageDown': case ' ': case 'j': e.preventDefault(); next(); break;
      case 'ArrowLeft': case 'PageUp': case 'k': e.preventDefault(); prev(); break;
      case 'Home': e.preventDefault(); show(0); break;
      case 'End': e.preventDefault(); show(total-1); break;
      case 'o': case 'O': e.preventDefault(); openDlg('overview'); break;
      case '/': e.preventDefault(); openDlg('search'); break;
      case 'n': case 'N': toggleNotes(); break;
      case 't': case 'T': toggleTheme(); break;
      case '?': e.preventDefault(); openDlg('help'); break;
      case 'g': jumpBuffer=''; break;
      default:
        if(/^[0-9]$/.test(e.key)){
          jumpBuffer+=e.key;
          clearTimeout(jumpTimer);
          jumpTimer=setTimeout(function(){
            var n=parseInt(jumpBuffer,10); jumpBuffer='';
            if(n>=1&&n<=total) show(n-1);
          },600);
        }
    }
  });
  var jumpBuffer='',jumpTimer=null;

  function toggleNotes(){
    var on=root.classList.toggle('show-notes');
    var b=document.getElementById('notes-btn');
    b.setAttribute('aria-pressed',on?'true':'false');
    try{localStorage.setItem('a11y-deck-notes',on?'1':'0');}catch(e){}
    live.textContent='Speaker notes '+(on?'shown':'hidden');
  }
  function toggleTheme(){
    var cur=root.getAttribute('data-theme');
    var next=cur==='dark'?'light':(cur==='light'?'':'dark');
    if(next) root.setAttribute('data-theme',next); else root.removeAttribute('data-theme');
    try{localStorage.setItem('a11y-deck-theme',next);}catch(e){}
    live.textContent='Theme: '+(next||'system');
  }

  // ---- search ----
  var input=document.getElementById('search-input');
  var results=document.getElementById('results');
  function runSearch(){
    var q=input.value.trim().toLowerCase();
    results.innerHTML='';
    if(q.length<2){return;}
    var hits=0;
    for(var i=0;i<INDEX.length&&hits<60;i++){
      var s=INDEX[i];
      if(s.h.indexOf(q)===-1) continue;
      hits++;
      var li=document.createElement('li');
      li.innerHTML="<button type='button' data-act='goto' data-n='"+s.n+"'>"+
        "<span class='rn'>"+s.n+"</span>"+s.t+"<span class='rm'>"+s.m+"</span></button>";
      results.appendChild(li);
    }
    if(!hits){results.innerHTML="<li><p>No slides match that.</p></li>";}
    document.getElementById('search-count').textContent=hits?(hits+' matching slides'):'';
  }
  input.addEventListener('input',runSearch);
  input.addEventListener('keydown',function(e){
    if(e.key==='Enter'){
      var b=results.querySelector('button');
      if(b){b.click();}
    }
  });

  // ---- boot ----
  var stored;
  try{stored=localStorage.getItem('a11y-deck-theme');}catch(e){}
  if(stored) root.setAttribute('data-theme',stored);
  try{if(localStorage.getItem('a11y-deck-notes')==='1'){
    root.classList.add('show-notes');
    document.getElementById('notes-btn').setAttribute('aria-pressed','true');
  }}catch(e){}

  var start=0;
  var m=/^#slide-(\d+)$/.exec(location.hash);
  if(m){start=parseInt(m[1],10)-1;}
  else{
    try{var s=localStorage.getItem('a11y-deck-slide'); if(s) start=parseInt(s,10)-1;}catch(e){}
  }
  show(clamp(start),{focus:false});

  window.addEventListener('hashchange',function(){
    var m=/^#slide-(\d+)$/.exec(location.hash);
    if(m){var n=parseInt(m[1],10)-1; if(n!==idx) show(n,{silent:true});}
  });
})();
"""


def js_literal(value) -> str:
    """JSON for embedding in an inline <script>.

    `<`, `>`, and `&` become unicode escapes so slide text containing markup -
    including a literal `</script>` in a code sample - can never terminate the
    element early or be re-parsed as HTML.
    """
    return (
        json.dumps(value, separators=(",", ":"))
        .replace("<", "\\u003c")
        .replace(">", "\\u003e")
        .replace("&", "\\u0026")
    )


def build_page(modules: list[Module], slides: list[Slide]) -> str:
    total = len(slides)
    index = [
        {
            "n": s.number,
            "t": html.escape(s.title),
            "m": html.escape(s.module),
            "h": (s.title + " " + s.module + " " + plain_text(s)).lower(),
        }
        for s in slides
    ]

    grid_parts = []
    for mod in modules:
        first = mod.slides[0].number
        last = mod.slides[-1].number
        grid_parts.append(
            f"<h3 class='modhead'><span>{html.escape(mod.name)}</span>"
            f"<span class='cnt'>{html.escape(mod.part)} &middot; slides {first}&ndash;{last}</span></h3>"
            "<div class='grid'>"
            + "".join(
                f"<button type='button' data-act='goto' data-n='{s.number}'>"
                f"<span class='gn'>{s.number}</span><br>{html.escape(s.title)}</button>"
                for s in mod.slides
            )
            + "</div>"
        )

    slides_html = "".join(render_slide(s, total) for s in slides)

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Chrome Accessibility: a {total}-slide course</title>
<meta name="description" content="A {total}-slide course on accessibility in Chrome and Chromium: the web platform side, DevTools, and the Chromium accessibility pipeline from Blink to platform APIs.">
<style>{CSS}</style>
</head>
<body>
<a class="skip" href="#deck">Skip to the slides</a>
<header class="topbar">
  <h1>Chrome Accessibility <span class="sub">&middot; {total} slides</span></h1>
  <span class="counter" id="counter">1 / {total}</span>
  <button class="btn" type="button" data-act="prev" aria-label="Previous slide">&larr;</button>
  <button class="btn" type="button" data-act="next" aria-label="Next slide">&rarr;</button>
  <button class="btn" type="button" data-act="open" data-target="overview">Contents</button>
  <button class="btn" type="button" data-act="open" data-target="search">Search</button>
  <button class="btn" type="button" id="notes-btn" data-act="notes" aria-pressed="false">Notes</button>
  <button class="btn" type="button" data-act="theme">Theme</button>
  <button class="btn" type="button" data-act="open" data-target="help" aria-label="Keyboard shortcuts">?</button>
</header>
<div class="progress"><div id="bar"></div></div>
<p class="visually-hidden" id="live" role="status" aria-live="polite"></p>

<p class="nojs-hint">JavaScript is off, so every slide is shown as one long document &mdash;
which is a perfectly good way to read it. Turn JavaScript on for one-slide-at-a-time
presentation, search, and speaker notes.</p>

<main id="deck">
{slides_html}
</main>

<div class="overlay" id="overview" role="dialog" aria-modal="true" aria-label="Table of contents">
  <div class="panel">
    <button class="btn close" type="button" data-act="close">Close</button>
    <h2>Contents</h2>
    {''.join(grid_parts)}
  </div>
</div>

<div class="overlay" id="search" role="dialog" aria-modal="true" aria-label="Search slides">
  <div class="panel">
    <button class="btn close" type="button" data-act="close">Close</button>
    <h2>Search</h2>
    <label class="visually-hidden" for="search-input">Search slide text</label>
    <input id="search-input" type="search" placeholder="e.g. AXTreeSerializer, aria-live, hit test" autocomplete="off">
    <p class="visually-hidden" id="search-count" role="status" aria-live="polite"></p>
    <ul class="results" id="results"></ul>
  </div>
</div>

<div class="overlay" id="help" role="dialog" aria-modal="true" aria-label="Keyboard shortcuts">
  <div class="panel">
    <button class="btn close" type="button" data-act="close">Close</button>
    <h2>Keyboard shortcuts</h2>
    <ul class="keys">
      <li><kbd>&rarr;</kbd> / <kbd>Space</kbd> / <kbd>j</kbd> &mdash; next slide</li>
      <li><kbd>&larr;</kbd> / <kbd>k</kbd> &mdash; previous slide</li>
      <li><kbd>Home</kbd> / <kbd>End</kbd> &mdash; first / last slide</li>
      <li>type a number &mdash; jump to that slide</li>
      <li><kbd>o</kbd> &mdash; contents</li>
      <li><kbd>/</kbd> &mdash; search</li>
      <li><kbd>n</kbd> &mdash; speaker notes</li>
      <li><kbd>t</kbd> &mdash; theme (system / dark / light)</li>
      <li><kbd>?</kbd> &mdash; this help</li>
      <li><kbd>Esc</kbd> &mdash; close a dialog</li>
    </ul>
    <p>Printing (or &ldquo;Save as PDF&rdquo;) gives you one slide per page, notes included.</p>
  </div>
</div>

<script>var INDEX={js_literal(index)};</script>
<script>{JS}</script>
</body>
</html>
"""


def plain_text(slide: Slide) -> str:
    parts: list[str] = []
    for kind, payload in slide.blocks:
        if kind == "p":
            parts.append(payload)
        elif kind == "code":
            parts.append(payload[1])
        elif kind == "callout":
            parts.append(payload[1])
        elif kind == "svg":
            parts.append(payload[0])
        elif kind == "list":
            parts.extend(t for _, t, _ in payload)
        elif kind == "table":
            for row in payload:
                parts.extend(row)
    parts.extend(slide.notes)
    return re.sub(r"\s+", " ", " ".join(parts))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="validate only, write nothing")
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args()

    paths = sorted(SLIDE_DIR.glob("[0-9]*.md"))
    if not paths:
        raise SystemExit(f"no slide sources found in {SLIDE_DIR}")

    modules = [parse_module(p) for p in paths]
    slides: list[Slide] = []
    for mod in modules:
        for i, slide in enumerate(mod.slides, 1):
            slide.number = len(slides) + 1
            slide.module_index = i
            slides.append(slide)

    titles: dict[str, str] = {}
    problems: list[str] = []
    for s in slides:
        key = s.title.lower()
        if key in titles:
            problems.append(f"duplicate slide title {s.title!r} ({titles[key]} and {s.source})")
        titles[key] = s.source
        if not s.blocks:
            problems.append(f"empty slide {s.number} {s.title!r} in {s.source}")
    if problems:
        for p in problems:
            print("error:", p, file=sys.stderr)
        return 1

    for mod in modules:
        print(f"{len(mod.slides):>4}  {mod.source:<28} {mod.name}")
    print(f"{len(slides):>4}  total")
    if len(slides) != EXPECTED_SLIDES:
        print(
            f"warning: {len(slides)} slides, expected {EXPECTED_SLIDES}",
            file=sys.stderr,
        )

    if args.check:
        return 0

    page = build_page(modules, slides)
    args.out.write_text(page, encoding="utf-8")
    print(f"wrote {args.out} ({len(page)/1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
