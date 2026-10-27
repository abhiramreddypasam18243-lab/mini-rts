"""Turns a Claude Code session log (.jsonl) into a turn-by-turn transcript:
transcript.md and a standalone, clickable transcript.html (each user turn
numbered, its response in a collapsed block).

Usage: python -I make_transcript.py <session.jsonl> <out_dir> <title>
"""
import html
import json
import os
import re
import sys
from datetime import datetime, timezone, timedelta

SRC, OUT, TITLE = sys.argv[1], sys.argv[2], sys.argv[3]
IST = timezone(timedelta(hours=5, minutes=30))

# --- reading the log ---------------------------------------------------------

def strip_reminders(t):
    t = re.sub(r"<system-reminder>.*?</system-reminder>", "", t, flags=re.S)
    return t.strip()


def redact(t):
    """Hides one-time sign-in codes (like GitHub's XXXX-XXXX device codes)."""
    return re.sub(r"\b[A-Z0-9]{4}-[A-Z0-9]{4}\b", "XXXX-XXXX", t)


def text_of(content):
    """Text of a user message, plus a note for attached images."""
    if isinstance(content, str):
        return strip_reminders(content), 0
    out, images = [], 0
    for b in content or []:
        if not isinstance(b, dict):
            continue
        if b.get("type") == "text":
            out.append(b.get("text", ""))
        elif b.get("type") == "image":
            images += 1
    return strip_reminders("\n".join(out)), images


def when(ts):
    try:
        d = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone(IST)
        return d.strftime("%d %b %Y, %H:%M")
    except Exception:
        return ""


def tool_line(block):
    name = block.get("name", "")
    inp = block.get("input", {}) or {}
    if name in ("Bash", "PowerShell"):
        return name, inp.get("description") or inp.get("command", "")[:120]
    if name in ("Read", "Write", "Edit"):
        return name, os.path.basename(str(inp.get("file_path", "")))
    if name in ("Grep", "Glob"):
        return name, inp.get("pattern", "")
    if name == "TaskCreate":
        return "Task", inp.get("subject", "")
    if name == "TaskUpdate":
        return "Task", "%s → %s" % (inp.get("taskId", ""), inp.get("status", ""))
    if name == "Monitor":
        return "Monitor", inp.get("description", "")
    if name == "WebSearch":
        return "Web search", inp.get("query", "")
    if name == "Skill":
        return "Skill", inp.get("skill", "")
    if name == "Agent":
        return "Agent", inp.get("description", "")
    return name, ""


def is_human(r):
    """A message the user typed (or a slash command), not a system event."""
    if r.get("type") != "user" or r.get("isMeta") or r.get("isCompactSummary") or r.get("isSidechain"):
        return False
    c = r.get("message", {}).get("content")
    if isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
        return False
    t, imgs = text_of(c)
    if not t and not imgs:
        return False
    for prefix in ("<task-notification", "<local-command-caveat", "<local-command-stdout", "<bash-stdout",
                   "[SYSTEM NOTIFICATION", "[Request interrupted", "This session is being continued",
                   "Caveat:", "<command-stdout"):
        if t.startswith(prefix):
            return False
    return True


turns = []          # {"ts", "text", "images", "items": [...]}
pre = []            # anything before the first turn
answered = {}       # tool_use_id -> answer text (AskUserQuestion)
seen_uuid = set()

with open(SRC, encoding="utf-8") as f:
    records = [json.loads(l) for l in f if l.strip()]

for r in records:
    if r.get("type") == "user":
        c = r.get("message", {}).get("content")
        if isinstance(c, list):
            for b in c:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    rc = b.get("content")
                    txt = rc if isinstance(rc, str) else " ".join(x.get("text", "") for x in rc or [] if isinstance(x, dict))
                    if "answered your questions" in txt or "questions have been answered" in txt:
                        answered[b.get("tool_use_id")] = txt

for r in records:
    u = r.get("uuid")
    if u in seen_uuid:
        continue
    if u:
        seen_uuid.add(u)
    if r.get("isSidechain"):
        continue
    typ = r.get("type")
    items = turns[-1]["items"] if turns else pre
    if typ == "user":
        c = r.get("message", {}).get("content")
        if is_human(r):
            t, imgs = text_of(c)
            m = re.search(r"<command-name>(.*?)</command-name>.*?<command-args>(.*?)</command-args>", t, re.S)
            if m:
                t = (m.group(1).strip() + " " + m.group(2).strip()).strip()
            turns.append({"ts": r.get("timestamp", ""), "text": t, "images": imgs, "items": []})
            continue
        t, _ = text_of(c) if not (isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)) else ("", 0)
        m = re.search(r"<(local-command-stdout|bash-stdout)>(.*?)</\1>", t or "", re.S)
        if m and m.group(2).strip():
            items.append({"kind": "output", "text": m.group(2).strip()})
        elif (t or "").startswith(("<task-notification", "[SYSTEM NOTIFICATION")):
            if items and items[-1].get("kind") == "event":
                continue
            items.append({"kind": "event", "text": "A background task finished; the work continued."})
    elif typ == "assistant":
        for b in r.get("message", {}).get("content", []) or []:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "text" and b.get("text", "").strip():
                items.append({"kind": "text", "text": b["text"].strip()})
            elif b.get("type") == "tool_use":
                if b.get("name") == "AskUserQuestion":
                    qs = b.get("input", {}).get("questions", [])
                    items.append({"kind": "ask", "questions": qs, "answer": answered.get(b.get("id"), "")})
                else:
                    name, what = tool_line(b)
                    items.append({"kind": "tool", "name": name, "what": what})

turns = [t for t in turns if t["text"] or t["images"]]

# --- a small Markdown renderer (no outside libraries) -------------------------

def inline(s):
    s = html.escape(s, quote=False)
    codes = []

    def keep(m):
        codes.append("<code>%s</code>" % m.group(1))
        return "\x00%d\x00" % (len(codes) - 1)
    s = re.sub(r"`([^`]+)`", keep, s)
    s = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2" target="_blank" rel="noopener">\1</a>', s)
    # Bare links stop before "*" (bold markers) and trailing punctuation.
    def bare(m):
        url = m.group(1).rstrip(".,;:")
        return '<a href="%s" target="_blank" rel="noopener">%s</a>%s' % (url, url, m.group(1)[len(url):])
    s = re.sub(r'(?<!["\'>=])(https?://[^\s<)*]+)', bare, s)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", s)
    s = re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], s)
    return s


def md(text):
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        if line.strip().startswith("```"):
            j = i + 1
            buf = []
            while j < len(lines) and not lines[j].strip().startswith("```"):
                buf.append(lines[j])
                j += 1
            out.append("<pre><code>%s</code></pre>" % html.escape("\n".join(buf)))
            i = j + 1
            continue
        if line.strip().startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            head = [c.strip() for c in line.strip().strip("|").split("|")]
            rows = []
            j = i + 2
            while j < len(lines) and lines[j].strip().startswith("|"):
                rows.append([c.strip() for c in lines[j].strip().strip("|").split("|")])
                j += 1
            t = "<div class=\"tbl\"><table><thead><tr>%s</tr></thead><tbody>%s</tbody></table></div>" % (
                "".join("<th>%s</th>" % inline(c) for c in head),
                "".join("<tr>%s</tr>" % "".join("<td>%s</td>" % inline(c) for c in row) for row in rows))
            out.append(t)
            i = j
            continue
        m = re.match(r"^(#{1,6})\s+(.*)", line)
        if m:
            lvl = min(len(m.group(1)) + 2, 6)
            out.append("<h%d>%s</h%d>" % (lvl, inline(m.group(2)), lvl))
            i += 1
            continue
        if re.match(r"^\s*([-*]|\d+\.)\s+", line):
            j = i
            buf = []
            while j < len(lines) and (re.match(r"^\s*([-*]|\d+\.)\s+", lines[j]) or (lines[j].startswith("  ") and lines[j].strip())):
                buf.append(lines[j])
                j += 1
            out.append(render_list(buf))
            i = j
            continue
        if line.startswith(">"):
            j = i
            buf = []
            while j < len(lines) and lines[j].startswith(">"):
                buf.append(lines[j][1:].strip())
                j += 1
            out.append("<blockquote>%s</blockquote>" % md("\n".join(buf)))
            i = j
            continue
        if not line.strip():
            i += 1
            continue
        j = i
        buf = []
        while j < len(lines) and lines[j].strip() and not re.match(r"^(#{1,6}\s|```|\s*([-*]|\d+\.)\s|\||>)", lines[j]):
            buf.append(lines[j])
            j += 1
        if not buf:
            buf, j = [line], i + 1
        out.append("<p>%s</p>" % "<br>".join(inline(b) for b in buf))
        i = j
    return "\n".join(out)


def render_list(buf):
    items = []
    for raw in buf:
        m = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)", raw)
        if m:
            items.append([len(m.group(1).replace("\t", "    ")), m.group(2)[-1] == ".", m.group(3)])
        elif items:
            items[-1][2] += " " + raw.strip()
    html_out = []
    stack = []
    for indent, ordered, body in items:
        while stack and indent < stack[-1][0]:
            html_out.append("</li></%s>" % ("ol" if stack.pop()[1] else "ul"))
        if not stack or indent > stack[-1][0]:
            html_out.append("<%s>" % ("ol" if ordered else "ul"))
            stack.append((indent, ordered))
        elif html_out:
            html_out.append("</li>")
        html_out.append("<li>%s" % inline(body))
    while stack:
        html_out.append("</li></%s>" % ("ol" if stack.pop()[1] else "ul"))
    return "".join(html_out)


# --- output: Markdown ---------------------------------------------------------

os.makedirs(OUT, exist_ok=True)
first, last = (when(turns[0]["ts"]), when(turns[-1]["ts"])) if turns else ("", "")
mdl = ["# %s" % TITLE, "", "Turn-by-turn transcript, %s to %s (%d turns). Times are IST." % (first, last, len(turns)), ""]
for n, t in enumerate(turns, 1):
    mdl += ["---", "", "## Turn %d (%s)" % (n, when(t["ts"])), "", "**User:**", ""]
    mdl += ["> " + l if l else ">" for l in t["text"].split("\n")]
    if t["images"]:
        mdl += [">", "> *[%d screenshot(s) attached]*" % t["images"]]
    mdl += ["", "**Response:**", ""]
    for it in t["items"]:
        if it["kind"] == "text":
            mdl += [it["text"], ""]
        elif it["kind"] == "tool":
            mdl += ["- *%s: %s*" % (it["name"], it["what"]), ""]
        elif it["kind"] == "ask":
            for q in it["questions"]:
                mdl += ["**Question:** %s" % q.get("question", "")]
                for o in q.get("options", []):
                    mdl += ["- %s: %s" % (o.get("label", ""), o.get("description", ""))]
            if it["answer"]:
                mdl += ["", "**Answer:** %s" % it["answer"].strip()]
            mdl += [""]
        elif it["kind"] == "output":
            mdl += ["```", it["text"], "```", ""]
        elif it["kind"] == "event":
            mdl += ["*(%s)*" % it["text"], ""]
with open(os.path.join(OUT, "transcript.md"), "w", encoding="utf-8", newline="\n") as f:
    f.write(redact("\n".join(mdl) + "\n"))

# --- output: HTML -------------------------------------------------------------

def render_items(items):
    parts = []
    tools = []

    def flush():
        if tools:
            lis = "".join("<li><span class=\"tn\">%s</span> %s</li>" % (html.escape(a), html.escape(b)) for a, b in tools)
            parts.append("<details class=\"tools\"><summary>%d action%s</summary><ul>%s</ul></details>" % (
                len(tools), "" if len(tools) == 1 else "s", lis))
            tools.clear()
    for it in items:
        if it["kind"] == "tool":
            tools.append((it["name"], it["what"]))
            continue
        flush()
        if it["kind"] == "text":
            parts.append("<div class=\"msg\">%s</div>" % md(it["text"]))
        elif it["kind"] == "ask":
            qs = []
            for q in it["questions"]:
                opts = "".join("<li><strong>%s</strong>: %s</li>" % (inline(o.get("label", "")), inline(o.get("description", ""))) for o in q.get("options", []))
                qs.append("<p class=\"q\">%s</p><ul>%s</ul>" % (inline(q.get("question", "")), opts))
            ans = ("<p class=\"a\"><strong>Answer:</strong> %s</p>" % inline(it["answer"].strip())) if it["answer"] else ""
            parts.append("<div class=\"ask\"><div class=\"tag\">Question to the user</div>%s%s</div>" % ("".join(qs), ans))
        elif it["kind"] == "output":
            parts.append("<pre class=\"out\"><code>%s</code></pre>" % html.escape(it["text"]))
        elif it["kind"] == "event":
            parts.append("<p class=\"event\">%s</p>" % html.escape(it["text"]))
    flush()
    return "\n".join(parts) or "<p class=\"event\">(no reply recorded)</p>"


cards = []
for n, t in enumerate(turns, 1):
    user = md(t["text"]) if t["text"] else ""
    if t["images"]:
        user += "<p class=\"event\">[%d screenshot%s attached]</p>" % (t["images"], "" if t["images"] == 1 else "s")
    words = sum(len(it.get("text", "").split()) for it in t["items"] if it["kind"] == "text")
    acts = sum(1 for it in t["items"] if it["kind"] == "tool")
    cards.append("""<section class="turn" id="turn-%d" data-search="%s">
<div class="head"><a class="num" href="#turn-%d">Turn %d</a><span class="time">%s</span></div>
<div class="user">%s</div>
<details class="resp"><summary><span class="lbl">Response</span><span class="meta">%d words · %d actions</span></summary>
<div class="body">%s</div></details>
</section>""" % (n, html.escape(t["text"].lower()[:400], quote=True), n, n, when(t["ts"]), user, words, acts, render_items(t["items"])))

nav = "".join("<a href=\"#turn-%d\" title=\"%s\">%d</a>" % (n, html.escape(t["text"][:80], quote=True), n) for n, t in enumerate(turns, 1))

page = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%(title)s</title>
<style>
:root{--bg:#f6f4ef;--card:#fff;--ink:#1d2330;--muted:#6b7280;--line:#e3ded3;--accent:#9a5b13;--accent-soft:#f4e7d3;--user:#eef3fb;--user-line:#c9d8ef;--code:#f3f1ec}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#15171c;--card:#1e2128;--ink:#e6e8ec;--muted:#9aa1ad;--line:#2f333c;--accent:#e2a25a;--accent-soft:#3a2d1c;--user:#1c2636;--user-line:#2e3f5a;--code:#262a32}}
:root[data-theme=dark]{--bg:#15171c;--card:#1e2128;--ink:#e6e8ec;--muted:#9aa1ad;--line:#2f333c;--accent:#e2a25a;--accent-soft:#3a2d1c;--user:#1c2636;--user-line:#2e3f5a;--code:#262a32}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
header{position:sticky;top:0;z-index:5;background:var(--bg);border-bottom:1px solid var(--line);padding:14px 16px}
.wrap{max-width:920px;margin:0 auto}
h1{font-size:22px;margin:0 0 2px}
.sub{color:var(--muted);font-size:14px;margin:0 0 10px}
.bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
.bar input{flex:1;min-width:180px;padding:7px 10px;border:1px solid var(--line);border-radius:8px;background:var(--card);color:var(--ink);font:inherit;font-size:14px}
.bar button{padding:7px 12px;border:1px solid var(--line);border-radius:8px;background:var(--card);color:var(--ink);font:inherit;font-size:14px;cursor:pointer}
.bar button:hover{border-color:var(--accent)}
nav{display:flex;flex-wrap:wrap;gap:4px;margin-top:10px;max-height:64px;overflow:auto}
nav a{font-size:12px;padding:2px 7px;border-radius:6px;background:var(--card);border:1px solid var(--line);color:var(--muted);text-decoration:none}
nav a:hover{color:var(--accent);border-color:var(--accent)}
main{padding:18px 16px 60px}
.turn{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin:0 0 14px;scroll-margin-top:170px}
.turn.hidden{display:none}
.head{display:flex;justify-content:space-between;align-items:baseline;gap:8px;margin-bottom:8px}
.num{font-weight:700;color:var(--accent);text-decoration:none;font-size:15px}
.time{color:var(--muted);font-size:13px}
.user{background:var(--user);border:1px solid var(--user-line);border-radius:9px;padding:8px 12px}
.user p{margin:4px 0}
details.resp{margin-top:10px}
details.resp>summary{cursor:pointer;list-style:none;display:flex;justify-content:space-between;align-items:center;padding:7px 10px;border-radius:8px;background:var(--accent-soft);font-size:14px}
details.resp>summary::-webkit-details-marker{display:none}
details.resp>summary .lbl::before{content:"\\25B8  ";color:var(--accent)}
details.resp[open]>summary .lbl::before{content:"\\25BE  "}
.lbl{font-weight:600}
.meta{color:var(--muted);font-size:12px}
.body{padding:6px 4px 0}
.msg{margin:10px 0}
.msg p{margin:8px 0}
.msg h3,.msg h4,.msg h5,.msg h6{margin:14px 0 6px;font-size:16px}
code{background:var(--code);border-radius:4px;padding:1px 4px;font-size:.88em}
pre{background:var(--code);border-radius:8px;padding:10px 12px;overflow:auto;font-size:13px;line-height:1.45}
pre code{background:none;padding:0}
.tbl{overflow-x:auto}
table{border-collapse:collapse;margin:8px 0;font-size:14px}
th,td{border:1px solid var(--line);padding:5px 9px;text-align:left;vertical-align:top}
th{background:var(--code)}
blockquote{margin:8px 0;padding:2px 12px;border-left:3px solid var(--line);color:var(--muted)}
details.tools{margin:8px 0;font-size:13px;color:var(--muted)}
details.tools summary{cursor:pointer}
details.tools ul{margin:4px 0 0;padding-left:20px}
.tn{display:inline-block;min-width:78px;font-weight:600;color:var(--ink)}
.ask{border:1px dashed var(--accent);border-radius:9px;padding:8px 12px;margin:10px 0}
.ask .tag{font-size:12px;color:var(--accent);font-weight:700;text-transform:uppercase;letter-spacing:.04em}
.ask .q{font-weight:600;margin:6px 0 2px}
.ask .a{margin:8px 0 2px}
.event{color:var(--muted);font-style:italic;font-size:13px;margin:8px 0}
a{color:var(--accent)}
@media (max-width:600px){.turn{padding:12px}.time{font-size:12px}}
</style>
</head>
<body>
<header><div class="wrap">
<h1>%(title)s</h1>
<p class="sub">%(count)d turns · %(first)s to %(last)s (IST) · click a turn's <b>Response</b> to expand it</p>
<div class="bar">
<input id="q" type="search" placeholder="Search your messages…" aria-label="Search turns">
<button id="open">Expand all</button><button id="close">Collapse all</button><button id="theme">Theme</button>
</div>
<nav>%(nav)s</nav>
</div></header>
<main class="wrap">
%(cards)s
</main>
<script>
const all=()=>document.querySelectorAll('details.resp');
document.getElementById('open').onclick=()=>all().forEach(d=>d.open=true);
document.getElementById('close').onclick=()=>all().forEach(d=>d.open=false);
document.getElementById('q').addEventListener('input',e=>{const v=e.target.value.trim().toLowerCase();
document.querySelectorAll('.turn').forEach(t=>t.classList.toggle('hidden',v&&!t.dataset.search.includes(v)));});
document.getElementById('theme').onclick=()=>{const r=document.documentElement;const dark=r.dataset.theme?r.dataset.theme==='dark':matchMedia('(prefers-color-scheme: dark)').matches;r.dataset.theme=dark?'light':'dark';};
if(location.hash){const d=document.querySelector(location.hash+' details.resp');if(d)d.open=true;}
</script>
</body>
</html>
""" % {"title": html.escape(TITLE), "count": len(turns), "first": first, "last": last, "nav": nav, "cards": "\n".join(cards)}

with open(os.path.join(OUT, "transcript.html"), "w", encoding="utf-8", newline="\n") as f:
    f.write(redact(page))
print("turns", len(turns), "first", first, "last", last)
print("html bytes", os.path.getsize(os.path.join(OUT, "transcript.html")))
