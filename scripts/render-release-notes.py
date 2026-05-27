#!/usr/bin/env python3
"""Render RELEASE_NOTES.md (a small Markdown subset) to HTML for the Sparkle
appcast <description>. Stdlib only — runs on the CI macOS runner with no deps.

Supports: `##`/`#` headings, `-`/`*` bullet lists, `**bold**`, `*italic*`,
`` `code` ``. Anything else becomes a paragraph. Output is UTF-8 HTML.

Usage:  render-release-notes.py RELEASE_NOTES.md
"""
import sys, re, html


def inline(s: str) -> str:
    s = html.escape(s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", r"<i>\1</i>", s)
    s = re.sub(r"`(.+?)`", r"<code>\1</code>", s)
    return s


def render(md: str) -> str:
    md = re.sub(r"<!--.*?-->", "", md, flags=re.DOTALL)   # drop HTML comments
    out, in_list = [], False

    def close_list():
        nonlocal in_list
        if in_list:
            out.append("</ul>")
            in_list = False

    for raw in md.splitlines():
        line = raw.strip()
        if not line:
            close_list()
        elif line.startswith("## "):
            close_list(); out.append(f"<h2>{inline(line[3:])}</h2>")
        elif line.startswith("# "):
            close_list(); out.append(f"<h1>{inline(line[2:])}</h1>")
        elif line.startswith(("- ", "* ")):
            if not in_list:
                out.append("<ul>"); in_list = True
            out.append(f"<li>{inline(line[2:])}</li>")
        else:
            close_list(); out.append(f"<p>{inline(line)}</p>")
    close_list()
    return "\n".join(out)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: render-release-notes.py RELEASE_NOTES.md")
    with open(sys.argv[1], encoding="utf-8") as f:
        # `>` is always escaped by inline(), so `]]>` can't occur in the output;
        # the replace is defense-in-depth so the result can never break the
        # appcast CDATA it gets embedded in.
        sys.stdout.write(render(f.read()).replace("]]>", "]]&gt;"))
