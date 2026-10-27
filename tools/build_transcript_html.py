"""Converts transcript.md into a responsive, standalone, searchable transcript.html
suitable for GitHub Pages hosting.
"""
import html
import re
import os
import sys

def render_markdown_fragment(md_text):
    lines = md_text.strip().split("\n")
    out = []
    in_code = False
    code_lang = ""
    code_lines = []
    in_table = False
    table_rows = []
    in_ul = False
    in_ol = False

    def close_lists():
        nonlocal in_ul, in_ol
        res = []
        if in_ul:
            res.append("</ul>")
            in_ul = False
        if in_ol:
            res.append("</ol>")
            in_ol = False
        return res

    def format_inline(text):
        # Escape HTML entities first (preserving special tags if any)
        text = html.escape(text)
        # Bold
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        # Inline code
        text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
        # Markdown links
        text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2" target="_blank">\1</a>', text)
        return text

    i = 0
    while i < len(lines):
        line = lines[i]

        # Code block fence
        if line.strip().startswith("```"):
            out.extend(close_lists())
            if in_code:
                code_content = html.escape("\n".join(code_lines))
                out.append(f'<pre><code class="language-{code_lang}">{code_content}</code></pre>')
                in_code = False
                code_lines = []
                code_lang = ""
            else:
                in_code = True
                code_lang = line.strip()[3:].strip()
                code_lines = []
            i += 1
            continue

        if in_code:
            code_lines.append(line)
            i += 1
            continue

        # Table rows
        if "|" in line and (line.strip().startswith("|") or line.strip().endswith("|")):
            out.extend(close_lists())
            # Check if separator row
            if re.match(r"^\|?\s*[-:]+[-| :]*\|?$", line.strip()):
                i += 1
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not in_table:
                in_table = True
                table_rows = []
            table_rows.append(cells)
            i += 1
            continue
        elif in_table:
            # End of table
            table_html = ['<div class="table-wrap"><table>']
            for row_idx, r in enumerate(table_rows):
                table_html.append("<tr>")
                tag = "th" if row_idx == 0 else "td"
                for cell in r:
                    table_html.append(f"<{tag}>{format_inline(cell)}</{tag}>")
                table_html.append("</tr>")
            table_html.append("</table></div>")
            out.extend(table_html)
            in_table = False
            table_rows = []

        # Empty line
        if not line.strip():
            out.extend(close_lists())
            i += 1
            continue

        # Headings
        if line.startswith("#### "):
            out.extend(close_lists())
            out.append(f"<h4>{format_inline(line[5:])}</h4>")
            i += 1
            continue
        elif line.startswith("### "):
            out.extend(close_lists())
            out.append(f"<h3>{format_inline(line[4:])}</h3>")
            i += 1
            continue
        elif line.startswith("## "):
            out.extend(close_lists())
            out.append(f"<h2>{format_inline(line[3:])}</h2>")
            i += 1
            continue

        # Blockquote
        if line.startswith("> "):
            out.extend(close_lists())
            out.append(f"<blockquote><p>{format_inline(line[2:])}</p></blockquote>")
            i += 1
            continue

        # Unordered list
        if line.strip().startswith("- ") or line.strip().startswith("* "):
            if not in_ul:
                out.extend(close_lists())
                out.append("<ul>")
                in_ul = True
            content = line.strip()[2:]
            out.append(f"<li>{format_inline(content)}</li>")
            i += 1
            continue

        # Ordered list
        m_ol = re.match(r"^\s*(\d+)\.\s+(.*)$", line)
        if m_ol:
            if not in_ol:
                out.extend(close_lists())
                out.append("<ol>")
                in_ol = True
            out.append(f"<li>{format_inline(m_ol.group(2))}</li>")
            i += 1
            continue

        # Regular paragraph
        out.extend(close_lists())
        out.append(f"<p>{format_inline(line)}</p>")
        i += 1

    if in_table:
        table_html = ['<div class="table-wrap"><table>']
        for row_idx, r in enumerate(table_rows):
            table_html.append("<tr>")
            tag = "th" if row_idx == 0 else "td"
            for cell in r:
                table_html.append(f"<{tag}>{format_inline(cell)}</{tag}>")
            table_html.append("</tr>")
        table_html.append("</table></div>")
        out.extend(table_html)

    out.extend(close_lists())
    return "\n".join(out)


def build_html(transcript_md_path, out_html_path):
    with open(transcript_md_path, "r", encoding="utf-8") as f:
        raw_text = f.read()

    # Split turns
    turn_blocks = re.split(r"\n##\s+(?:Turn\s+)?(\d+)\s*\n", raw_text)
    
    turns = []
    # If the first item is header text, extract metadata
    header_info = turn_blocks[0]
    for i in range(1, len(turn_blocks), 2):
        turn_num = int(turn_blocks[i])
        body = turn_blocks[i+1]
        
        # Split user and assistant
        parts = re.split(r"\n###\s+User\s*\n", body, maxsplit=1)
        if len(parts) == 2:
            subparts = re.split(r"\n###\s+Assistant\s*\n", parts[1], maxsplit=1)
            user_text = subparts[0].strip()
            assistant_text = subparts[1].strip() if len(subparts) > 1 else ""
        else:
            user_text = ""
            assistant_text = body.strip()

        turns.append({
            "num": turn_num,
            "user": user_text,
            "assistant": assistant_text
        })

    # Generate Navigation Pills
    nav_pills = []
    for t in turns:
        num = t["num"]
        nav_pills.append(f'<a href="#turn-{num}" class="turn-pill" title="Jump to Turn {num}">Turn {num}</a>')
    nav_html = "\n".join(nav_pills)

    # Generate Turn Cards
    turns_html = []
    for t in turns:
        num = t["num"]
        user_rendered = render_markdown_fragment(t["user"])
        assistant_rendered = render_markdown_fragment(t["assistant"])
        card = f"""
        <article class="turn-card" id="turn-{num}" data-turn="{num}">
          <header class="turn-header">
            <div class="turn-title-wrap">
              <span class="turn-badge">Turn {num}</span>
              <a href="#turn-{num}" class="turn-anchor" aria-label="Direct link to Turn {num}">#</a>
            </div>
            <button class="copy-btn" onclick="copyTurn({num})" title="Copy turn link">Copy link</button>
          </header>
          
          <div class="turn-section user-section">
            <div class="speaker-label">User Prompt</div>
            <div class="section-content">{user_rendered}</div>
          </div>
          
          <div class="turn-section assistant-section">
            <div class="speaker-label">Assistant Response</div>
            <div class="section-content">{assistant_rendered}</div>
          </div>
        </article>
        """
        turns_html.append(card)

    all_turns_html = "\n".join(turns_html)

    html_page = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Mini RTS — Session Transcript & Viva Notes</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cinzel:wght@700&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
  <style>
    :root {{
      --bg: #0c1017;
      --card-bg: #141a24;
      --user-bg: #182234;
      --border: #232c3d;
      --border-focus: #3d4f6d;
      --text: #e2e8f0;
      --text-muted: #8e9db3;
      --gold: #d4a359;
      --gold-soft: rgba(212, 163, 89, 0.15);
      --accent: #38bdf8;
      --accent-soft: rgba(56, 189, 248, 0.12);
      --code-bg: #090d14;
      --font-sans: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      --font-mono: 'JetBrains Mono', Consolas, monospace;
    }}

    [data-theme="light"] {{
      --bg: #f8fafc;
      --card-bg: #ffffff;
      --user-bg: #f0f6ff;
      --border: #e2e8f0;
      --border-focus: #94a3b8;
      --text: #0f172a;
      --text-muted: #64748b;
      --gold: #b47828;
      --gold-soft: rgba(180, 120, 40, 0.12);
      --accent: #0284c7;
      --accent-soft: rgba(2, 132, 199, 0.1);
      --code-bg: #f1f5f9;
    }}

    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    html {{ scroll-behavior: smooth; }}
    body {{
      font-family: var(--font-sans);
      background: var(--bg);
      color: var(--text);
      line-height: 1.65;
      font-size: 15px;
      -webkit-font-smoothing: antialiased;
    }}

    /* Top Sticky Navigation Bar */
    header.site-header {{
      position: sticky;
      top: 0;
      z-index: 100;
      background: var(--bg);
      border-bottom: 1px solid var(--border);
      backdrop-filter: blur(12px);
      padding: 12px 20px;
    }}
    .header-inner {{
      max-width: 1040px;
      margin: 0 auto;
      display: flex;
      flex-direction: column;
      gap: 10px;
    }}
    .header-top {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      flex-wrap: wrap;
      gap: 12px;
    }}
    .brand {{
      display: flex;
      align-items: center;
      gap: 12px;
    }}
    .brand h1 {{
      font-family: 'Cinzel', serif;
      font-size: 20px;
      letter-spacing: 0.05em;
      color: var(--gold);
    }}
    .status-tag {{
      display: inline-block;
      font-size: 11px;
      text-transform: uppercase;
      font-weight: 700;
      padding: 2px 8px;
      border-radius: 999px;
      background: rgba(34, 197, 94, 0.15);
      color: #22c55e;
      border: 1px solid rgba(34, 197, 94, 0.3);
    }}
    .header-actions {{
      display: flex;
      align-items: center;
      gap: 10px;
    }}
    .btn {{
      padding: 6px 14px;
      border-radius: 8px;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      text-decoration: none;
      transition: all 0.15s ease;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      border: 1px solid var(--border);
      background: var(--card-bg);
      color: var(--text);
    }}
    .btn:hover {{
      border-color: var(--gold);
      color: var(--gold);
    }}
    .btn-primary {{
      background: var(--gold);
      color: #0c1017;
      border-color: var(--gold);
    }}
    .btn-primary:hover {{
      background: #e5b369;
      color: #0c1017;
    }}

    /* Search & Filter */
    .search-bar {{
      display: flex;
      gap: 8px;
      align-items: center;
    }}
    .search-input {{
      flex: 1;
      padding: 8px 14px;
      border-radius: 8px;
      border: 1px solid var(--border);
      background: var(--card-bg);
      color: var(--text);
      font-size: 14px;
      font-family: inherit;
    }}
    .search-input:focus {{
      outline: none;
      border-color: var(--accent);
    }}

    /* Turn Pills */
    .nav-pills {{
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      max-height: 48px;
      overflow-y: auto;
      padding-top: 4px;
    }}
    .turn-pill {{
      font-size: 12px;
      font-weight: 600;
      padding: 3px 10px;
      border-radius: 6px;
      background: var(--card-bg);
      border: 1px solid var(--border);
      color: var(--text-muted);
      text-decoration: none;
      transition: all 0.15s;
    }}
    .turn-pill:hover {{
      color: var(--gold);
      border-color: var(--gold);
    }}

    /* Content Container */
    main.container {{
      max-width: 1040px;
      margin: 24px auto 80px;
      padding: 0 16px;
    }}

    /* Turn Cards */
    .turn-card {{
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 14px;
      margin-bottom: 24px;
      overflow: hidden;
      scroll-margin-top: 140px;
      box-shadow: 0 4px 16px rgba(0,0,0,0.12);
      transition: border-color 0.2s;
    }}
    .turn-card:hover {{
      border-color: var(--border-focus);
    }}
    .turn-header {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 18px;
      background: rgba(0, 0, 0, 0.15);
      border-bottom: 1px solid var(--border);
    }}
    .turn-title-wrap {{
      display: flex;
      align-items: center;
      gap: 10px;
    }}
    .turn-badge {{
      font-weight: 700;
      font-size: 14px;
      color: var(--gold);
      background: var(--gold-soft);
      padding: 2px 10px;
      border-radius: 6px;
    }}
    .turn-anchor {{
      color: var(--text-muted);
      text-decoration: none;
      font-weight: bold;
    }}
    .turn-anchor:hover {{
      color: var(--gold);
    }}
    .copy-btn {{
      background: none;
      border: 1px solid var(--border);
      color: var(--text-muted);
      font-size: 12px;
      padding: 4px 10px;
      border-radius: 6px;
      cursor: pointer;
    }}
    .copy-btn:hover {{
      color: var(--text);
      border-color: var(--border-focus);
    }}

    /* Turn Sections */
    .turn-section {{
      padding: 18px 20px;
    }}
    .user-section {{
      background: var(--user-bg);
      border-bottom: 1px solid var(--border);
    }}
    .speaker-label {{
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--text-muted);
      margin-bottom: 8px;
    }}
    .user-section .speaker-label {{
      color: var(--accent);
    }}

    /* Markdown Styling */
    .section-content h2,
    .section-content h3,
    .section-content h4 {{
      margin: 18px 0 8px;
      color: var(--gold);
    }}
    .section-content h3 {{ font-size: 17px; }}
    .section-content h4 {{ font-size: 15px; color: var(--text); }}
    .section-content p {{
      margin-bottom: 12px;
    }}
    .section-content ul,
    .section-content ol {{
      margin: 8px 0 14px 24px;
    }}
    .section-content li {{
      margin-bottom: 6px;
    }}
    .section-content code {{
      font-family: var(--font-mono);
      font-size: 0.9em;
      background: var(--code-bg);
      padding: 2px 6px;
      border-radius: 5px;
      border: 1px solid rgba(255,255,255,0.06);
    }}
    .section-content pre {{
      background: var(--code-bg);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 14px 16px;
      overflow-x: auto;
      margin: 14px 0;
      font-size: 13.5px;
    }}
    .section-content pre code {{
      background: none;
      padding: 0;
      border: none;
    }}
    .table-wrap {{
      overflow-x: auto;
      margin: 16px 0;
      border-radius: 8px;
      border: 1px solid var(--border);
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 14px;
    }}
    th, td {{
      padding: 10px 14px;
      text-align: left;
      border-bottom: 1px solid var(--border);
    }}
    th {{
      background: rgba(0, 0, 0, 0.2);
      color: var(--gold);
      font-weight: 600;
    }}
    blockquote {{
      border-left: 3px solid var(--gold);
      background: var(--gold-soft);
      padding: 10px 16px;
      border-radius: 0 8px 8px 0;
      margin: 14px 0;
      color: var(--text);
    }}
    a {{
      color: var(--accent);
      text-decoration: none;
    }}
    a:hover {{
      text-decoration: underline;
    }}

    /* Hidden cards during search */
    .turn-card.is-hidden {{
      display: none !important;
    }}

    @media (max-width: 768px) {{
      .site-header {{ padding: 10px 14px; }}
      .brand h1 {{ font-size: 17px; }}
      .turn-section {{ padding: 14px 14px; }}
      .nav-pills {{ max-height: 38px; }}
    }}
  </style>
</head>
<body>
  <header class="site-header">
    <div class="header-inner">
      <div class="header-top">
        <div class="brand">
          <h1>MINI RTS</h1>
          <span class="status-tag">252/252 Tests Passing</span>
        </div>
        <div class="header-actions">
          <button class="btn" onclick="toggleTheme()" id="theme-btn">☀️ Light</button>
          <a href="https://abhiramreddypasam18243-lab.github.io/mini-rts/" class="btn btn-primary" target="_blank">🎮 Play Game</a>
          <a href="https://github.com/abhiramreddypasam18243-lab/mini-rts" class="btn" target="_blank">GitHub Repo ↗</a>
        </div>
      </div>
      <div class="search-bar">
        <input type="text" id="search-input" class="search-input" placeholder="Search questions, A*, FSM, Nginx, seeding, combat..." oninput="filterTurns()">
      </div>
      <div class="nav-pills">
        {nav_html}
      </div>
    </div>
  </header>

  <main class="container">
    {all_turns_html}
  </main>

  <script>
    function toggleTheme() {{
      const current = document.documentElement.getAttribute('data-theme');
      const next = current === 'light' ? 'dark' : 'light';
      document.documentElement.setAttribute('data-theme', next);
      document.getElementById('theme-btn').textContent = next === 'light' ? '🌙 Dark' : '☀️ Light';
      localStorage.setItem('theme', next);
    }}

    const savedTheme = localStorage.getItem('theme');
    if (savedTheme) {{
      document.documentElement.setAttribute('data-theme', savedTheme);
      document.getElementById('theme-btn').textContent = savedTheme === 'light' ? '🌙 Dark' : '☀️ Light';
    }}

    function filterTurns() {{
      const query = document.getElementById('search-input').value.toLowerCase().trim();
      const cards = document.querySelectorAll('.turn-card');
      cards.forEach(card => {{
        const text = card.textContent.toLowerCase();
        if (!query || text.includes(query)) {{
          card.classList.remove('is-hidden');
        }} else {{
          card.classList.add('is-hidden');
        }}
      }});
    }}

    function copyTurn(num) {{
      const url = window.location.origin + window.location.pathname + '#turn-' + num;
      navigator.clipboard.writeText(url).then(() => {{
        alert('Copied link for Turn ' + num + ' to clipboard!');
      }}).catch(() => {{
        prompt('Copy link to Turn ' + num + ':', url);
      }});
    }}
  </script>
</body>
</html>
"""

    # Ensure output directory exists
    os.makedirs(os.path.dirname(out_html_path), exist_ok=True)
    with open(out_html_path, "w", encoding="utf-8") as f:
        f.write(html_page)

    print(f"Successfully generated {out_html_path} from {transcript_md_path} ({len(turns)} turns)")


if __name__ == "__main__":
    src_md = sys.argv[1] if len(sys.argv) > 1 else "transcript.md"
    out_html = sys.argv[2] if len(sys.argv) > 2 else "docs/transcript/transcript.html"
    build_html(src_md, out_html)
