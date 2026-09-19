#!/usr/bin/env python3
"""Generate a single self-contained HTML patcher.

The distribution used to be a folder: patch, applier, instructions, hashes and
a player README. That is a lot of ceremony for an 836-byte patch, and the
applier needed Python installed. This produces one file instead, which does the
whole job offline in a browser - verify the source ROM, strip a copier header,
apply the patch, verify the result, hand back a download.

The patch and both hashes are baked in at build time so they cannot drift from
the ROM they were built against.

SHA-1 is implemented in JavaScript rather than using crypto.subtle, because a
page opened from file:// is not a secure context in Chrome and crypto.subtle is
undefined there. The whole point is that this works as a local file.
"""

import argparse
import base64
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_SHA1 = "a6dc126a1da593d900b33eb74cf33403075e9525"


def controls_table(readme):
    """Lift the controls and progress tables out of README.md."""
    lines = readme.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.startswith("## Using the practice ROM"))
    except StopIteration:
        sys.exit("error: README.md has no '## Using the practice ROM' section")
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    return "\n".join(lines[start + 1:end]).strip()


def md_to_html(md):
    """Enough Markdown for the section we lift: headings, tables, bold, code.

    Paragraphs are joined before inline conversion, because the source is
    hard-wrapped and **bold** routinely spans a line break - converting line by
    line leaves the asterisks visible.
    """
    out, rows, para = [], [], []

    def inline(t):
        t = (t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
        t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
        t = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", t)
        t = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", t)
        return t

    def flush_table():
        if not rows:
            return
        head, body = rows[0], rows[2:]
        out.append("<table><thead><tr>"
                   + "".join(f"<th>{c}</th>" for c in head) + "</tr></thead><tbody>")
        for r in body:
            out.append("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>")
        out.append("</tbody></table>")
        rows.clear()

    def flush_para():
        if not para:
            return
        text = " ".join(para)
        cls = ""
        if text.startswith("- "):
            text, cls = text[2:], " class=bullet"
        out.append(f"<p{cls}>{inline(text)}</p>")
        para.clear()

    for line in md.splitlines():
        s = line.strip()
        if s.startswith("|"):
            flush_para()
            rows.append([inline(c.strip()) for c in s.strip("|").split("|")])
            continue
        flush_table()
        if not s:
            flush_para()
            continue
        if s.startswith("### "):
            flush_para()
            out.append(f"<h3>{inline(s[4:])}</h3>")
            continue
        if s.startswith("- "):
            flush_para()
        para.append(s)
    flush_para()
    flush_table()
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ips", type=Path, required=True)
    ap.add_argument("--rom", type=Path, required=True, help="the patched ROM, for its hash")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    ips = args.ips.read_bytes()
    result_sha1 = hashlib.sha1(args.rom.read_bytes()).hexdigest()
    version = (ROOT / "VERSION").read_text().strip()
    body = md_to_html(controls_table((ROOT / "README.md").read_text()))

    html = (ROOT / "tools/patcher.html.in").read_text()
    for key, value in {
        "@VERSION@": version,
        "@IPS_B64@": base64.b64encode(ips).decode(),
        "@SOURCE_SHA1@": SOURCE_SHA1,
        "@RESULT_SHA1@": result_sha1,
        "@BODY@": body,
    }.items():
        html = html.replace(key, value)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(html)
    print(f"wrote {args.out}  ({len(html):,} bytes, single file)")
    print(f"  patch     {len(ips):,} bytes embedded")
    print(f"  source    {SOURCE_SHA1}")
    print(f"  result    {result_sha1}")


if __name__ == "__main__":
    main()
