#!/usr/bin/env python3
# Tiny no-API-key web search for Pip. Scrapes DuckDuckGo's HTML endpoint and
# prints the top results as compact text the LLM can read. Swap this file to
# change backend (SearXNG, Brave API, etc.) — Pip just runs it with a query arg.
import sys, re, html, urllib.parse, urllib.request

def fetch(url, data=None):
    req = urllib.request.Request(url, data=data, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
    })
    with urllib.request.urlopen(req, timeout=12) as r:
        return r.read().decode("utf-8", "ignore")

def strip(s):
    return html.unescape(re.sub(r"<[^>]+>", "", s)).strip()

def search(query, n=4):
    q = urllib.parse.quote(query)
    out = []
    try:
        page = fetch("https://html.duckduckgo.com/html/?q=" + q)
        titles  = re.findall(r'<a[^>]*class="result__a"[^>]*>(.*?)</a>', page, re.S)
        snippets = re.findall(r'class="result__snippet"[^>]*>(.*?)</a>', page, re.S)
        for i in range(min(n, len(titles))):
            t = strip(titles[i])
            s = strip(snippets[i]) if i < len(snippets) else ""
            if t:
                out.append(f"{i+1}. {t} — {s}")
    except Exception:
        pass
    if not out:
        # fallback: lite endpoint
        try:
            page = fetch("https://lite.duckduckgo.com/lite/", data=("q=" + q).encode())
            rows = re.findall(r'class="result-snippet">(.*?)</td>', page, re.S)
            for i, s in enumerate(rows[:n]):
                s = strip(s)
                if s:
                    out.append(f"{i+1}. {s}")
        except Exception:
            pass
    return out

if __name__ == "__main__":
    query = " ".join(sys.argv[1:]).strip()
    if not query:
        print("NO_QUERY"); sys.exit(0)
    res = search(query)
    if not res:
        print("NO_RESULTS")
    else:
        text = "\n".join(res)
        print(text[:900])   # keep context small for the 3B
