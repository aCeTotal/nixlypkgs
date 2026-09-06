#!/usr/bin/env python3
"""Nixly AI — terminal client for the local RAG-backed coder model.

Pipeline:
  1. Hit /api/search on $NIXLY_RAG_URL for top-K chunks.
  2. Embed them in the prompt as CONTEXT.
  3. Stream the answer from local Ollama, rendered as live markdown.

Auth: bearer in $NIXLY_RAG_TOKEN, else first non-comment line of
$NIXLY_RAG_TOKEN_FILE (default /etc/nixly-ai/token).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator

import httpx
from prompt_toolkit import PromptSession
from prompt_toolkit.formatted_text import HTML
from prompt_toolkit.history import FileHistory
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.styles import Style as PTStyle
from rich.box import ROUNDED
from rich.console import Console, Group
from rich.live import Live
from rich.markdown import Markdown
from rich.panel import Panel
from rich.table import Table
from rich.text import Text


DEFAULT_RAG_URL = os.environ.get("NIXLY_RAG_URL", "https://ai.aceclan.no")
DEFAULT_OLLAMA = os.environ.get("NIXLY_OLLAMA_URL", "http://127.0.0.1:11434")
DEFAULT_MODEL = os.environ.get("NIXLY_AI_MODEL", "qwen2.5-coder:14b-instruct")
DEFAULT_TOKEN_FILE = os.environ.get("NIXLY_RAG_TOKEN_FILE", "/etc/nixly-ai/token")
HISTORY_DIR = Path(os.environ.get("XDG_STATE_HOME",
                                  str(Path.home() / ".local/state"))) / "nixly-ai"

SYSTEM_PROMPT = (
    "You are an expert programming assistant with access to a curated "
    "code+docs corpus across many languages, with a strong focus on Nix, "
    "NixOS and the wider open-source ecosystem. Use the provided CONTEXT "
    "blocks to ground your answer; cite sources by their [N] index. "
    "If the context does not cover a question, say so plainly and answer "
    "from your general knowledge."
)


# token + RAG plumbing

def load_token() -> str:
    t = os.environ.get("NIXLY_RAG_TOKEN", "").strip()
    if t:
        return t
    try:
        for line in Path(DEFAULT_TOKEN_FILE).read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                return line
    except (FileNotFoundError, PermissionError):
        return ""
    return ""


def search(rag_url: str, token: str, query: str, k: int,
           lang: str | None) -> tuple[list[dict], str | None]:
    headers = {"content-type": "application/json"}
    if token:
        headers["authorization"] = f"Bearer {token}"
    payload: dict = {"query": query, "k": k, "rerank": True}
    if lang:
        payload["lang"] = lang
    try:
        r = httpx.post(f"{rag_url}/api/search", headers=headers,
                       json=payload, timeout=60.0)
        r.raise_for_status()
    except httpx.HTTPStatusError as e:
        return [], f"HTTP {e.response.status_code} {e.response.text[:160]}"
    except httpx.HTTPError as e:
        return [], str(e)
    return r.json().get("chunks", []), None


def build_user_msg(question: str, chunks: list[dict]) -> str:
    if not chunks:
        return question
    parts = []
    for i, c in enumerate(chunks, 1):
        snippet = (c.get("text") or "")[:1800]
        parts.append(
            f"[{i}] file: {c.get('file', '?')}  lang: {c.get('lang', '?')}\n{snippet}"
        )
    ctx = "\n\n---\n\n".join(parts)
    return (f"CONTEXT:\n{ctx}\n\nQUESTION: {question}\n\n"
            "Answer concisely. Cite sources as [N]. If the context is "
            "insufficient, say so before answering from general knowledge.")


def chat_stream(ollama_url: str, model: str, messages: list[dict],
                num_ctx: int) -> Iterator[str]:
    payload = {"model": model, "messages": messages, "stream": True,
               "options": {"temperature": 0.2, "num_ctx": num_ctx}}
    with httpx.stream("POST", f"{ollama_url}/api/chat",
                      json=payload, timeout=None) as r:
        r.raise_for_status()
        for line in r.iter_lines():
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            tok = obj.get("message", {}).get("content")
            if tok:
                yield tok
            if obj.get("done"):
                break


# session state

@dataclass
class Settings:
    rag_url: str
    ollama_url: str
    model: str
    k: int
    lang: str | None
    num_ctx: int
    no_rag: bool


@dataclass
class Session:
    settings: Settings
    history: list[dict] = field(default_factory=list)
    last_sources: list[dict] = field(default_factory=list)


# rich rendering

def banner(console: Console, s: Settings) -> None:
    info = Text.assemble(
        ("model   ", "dim"), (s.model, "white"), "\n",
        ("rag     ", "dim"), (s.rag_url, "white"),
        ("  ", ""), ("(off)" if s.no_rag else "(on)",
                     "yellow" if s.no_rag else "green"), "\n",
        ("ollama  ", "dim"), (s.ollama_url, "white"), "\n",
        ("k       ", "dim"), (str(s.k), "white"),
        ("    lang ", "dim"), (s.lang or "any", "white"),
        ("    ctx ", "dim"), (str(s.num_ctx), "white"),
    )
    body = Group(
        Text.assemble(
            ("✱ ", "bold cyan"), ("nixly-ai", "bold white"),
            ("   retrieval-augmented coder", "dim"),
        ),
        Text(""),
        info,
        Text(""),
        Text("  /help   /sources   /clear   /model   /k   /lang   /no-rag   /exit",
             style="dim"),
    )
    console.print(Panel(body, box=ROUNDED, border_style="cyan",
                        padding=(1, 2), title="welcome", title_align="left"))


def sources_panel(chunks: list[dict]) -> Panel:
    t = Table.grid(padding=(0, 1))
    t.add_column(style="cyan", no_wrap=True)
    t.add_column(style="white", overflow="fold")
    t.add_column(style="dim", no_wrap=True, justify="right")
    for i, c in enumerate(chunks, 1):
        score = c.get("score", 0.0)
        t.add_row(f"[{i}]", c.get("file", "?"),
                  f"{c.get('lang', '?')}  ·  {score:.3f}")
    return Panel(t, box=ROUNDED, border_style="grey50",
                 title=f"sources · {len(chunks)}", title_align="left",
                 padding=(0, 1))


def assistant_panel(md_text: str, model: str) -> Panel:
    body = Markdown(md_text or "▍", code_theme="monokai")
    return Panel(body, box=ROUNDED, border_style="green",
                 title=f"✦ {model}", title_align="left",
                 padding=(1, 2))


def user_panel(text: str) -> Panel:
    return Panel(Text(text, style="white"), box=ROUNDED,
                 border_style="blue", title="❯ you", title_align="left",
                 padding=(0, 2))


# one chat turn

def run_turn(console: Console, sess: Session, question: str,
             plain: bool = False) -> None:
    if not plain:
        console.print(user_panel(question))

    chunks: list[dict] = []
    err: str | None = None
    if not sess.settings.no_rag:
        token = load_token()
        if plain:
            chunks, err = search(sess.settings.rag_url, token, question,
                                 sess.settings.k, sess.settings.lang)
        else:
            with console.status("[cyan]searching corpus[/]…", spinner="dots"):
                chunks, err = search(sess.settings.rag_url, token, question,
                                     sess.settings.k, sess.settings.lang)
        if err and not plain:
            console.print(f"[yellow]rag search failed:[/] {err}")
    sess.last_sources = chunks
    if chunks and not plain:
        console.print(sources_panel(chunks))

    user_msg = build_user_msg(question, chunks)
    sess.history.append({"role": "user", "content": user_msg})
    messages = [{"role": "system", "content": SYSTEM_PROMPT}, *sess.history]

    buf: list[str] = []
    try:
        if plain:
            for tok in chat_stream(sess.settings.ollama_url,
                                   sess.settings.model, messages,
                                   sess.settings.num_ctx):
                buf.append(tok)
                sys.stdout.write(tok)
                sys.stdout.flush()
            sys.stdout.write("\n")
        else:
            with Live(assistant_panel("", sess.settings.model),
                      console=console, refresh_per_second=14,
                      vertical_overflow="visible") as live:
                for tok in chat_stream(sess.settings.ollama_url,
                                       sess.settings.model, messages,
                                       sess.settings.num_ctx):
                    buf.append(tok)
                    live.update(assistant_panel("".join(buf),
                                                sess.settings.model))
    except httpx.HTTPError as e:
        console.print(f"[red]ollama chat failed:[/] {e}")
        sess.history.pop()
        return
    except KeyboardInterrupt:
        console.print("[yellow]interrupted[/]")
    finally:
        answer = "".join(buf).strip()
        if answer:
            sess.history.append({"role": "assistant", "content": answer})
        else:
            sess.history.pop()


# slash commands

SLASH_HELP = """\
**slash commands**

| command          | effect                            |
|------------------|-----------------------------------|
| `/help`          | this help                         |
| `/clear`         | drop chat history                 |
| `/sources`       | re-show sources from last turn    |
| `/model <name>`  | switch Ollama model               |
| `/k <n>`         | top-K chunks                      |
| `/lang <x>`      | language filter (`any` to clear)  |
| `/no-rag`        | toggle retrieval                  |
| `/exit` `/quit`  | leave                             |

**input**: Enter sends · Alt+Enter inserts newline · Ctrl-D exits.
"""


def handle_slash(console: Console, sess: Session, line: str) -> bool:
    parts = line.strip().split(None, 1)
    cmd = parts[0]
    arg = parts[1].strip() if len(parts) > 1 else ""
    if cmd in ("/exit", "/quit", ":q"):
        raise SystemExit(0)
    if cmd == "/help":
        console.print(Panel(Markdown(SLASH_HELP), box=ROUNDED,
                            border_style="cyan", padding=(0, 2)))
        return True
    if cmd == "/clear":
        sess.history.clear()
        sess.last_sources.clear()
        console.print("[dim]history cleared[/]")
        return True
    if cmd == "/sources":
        if sess.last_sources:
            console.print(sources_panel(sess.last_sources))
        else:
            console.print("[dim]no sources yet[/]")
        return True
    if cmd == "/model":
        if arg:
            sess.settings.model = arg
        console.print(f"[dim]model = [/]{sess.settings.model}")
        return True
    if cmd == "/k":
        try:
            sess.settings.k = max(1, int(arg))
        except ValueError:
            console.print("[red]/k expects an integer[/]")
        console.print(f"[dim]k = [/]{sess.settings.k}")
        return True
    if cmd == "/lang":
        sess.settings.lang = None if arg in ("", "any") else arg
        console.print(f"[dim]lang = [/]{sess.settings.lang or 'any'}")
        return True
    if cmd == "/no-rag":
        sess.settings.no_rag = not sess.settings.no_rag
        console.print(f"[dim]rag = [/]{'off' if sess.settings.no_rag else 'on'}")
        return True
    if cmd.startswith("/"):
        console.print(f"[red]unknown command:[/] {cmd}  — try /help")
        return True
    return False


# prompt_toolkit input

def make_prompt_session() -> PromptSession:
    HISTORY_DIR.mkdir(parents=True, exist_ok=True)
    style = PTStyle.from_dict({"prompt": "ansicyan bold"})
    kb = KeyBindings()

    @kb.add("escape", "enter")
    def _(event):
        event.current_buffer.insert_text("\n")

    return PromptSession(
        history=FileHistory(str(HISTORY_DIR / "history")),
        multiline=False,
        style=style,
        key_bindings=kb,
        prompt_continuation=lambda *_: HTML("<ansicyan>… </ansicyan>"),
    )


def repl(console: Console, sess: Session) -> int:
    banner(console, sess.settings)
    pt = make_prompt_session()
    while True:
        try:
            line = pt.prompt(HTML("<ansicyan><b>❯ </b></ansicyan>"))
        except EOFError:
            console.print()
            return 0
        except KeyboardInterrupt:
            continue
        if not line.strip():
            continue
        if handle_slash(console, sess, line):
            continue
        run_turn(console, sess, line)


# entry

def main() -> int:
    p = argparse.ArgumentParser(prog="ai", description=__doc__)
    p.add_argument("question", nargs="*", help="question; omit for chat REPL")
    p.add_argument("--rag-url", default=DEFAULT_RAG_URL)
    p.add_argument("--ollama-url", default=DEFAULT_OLLAMA)
    p.add_argument("--model", default=DEFAULT_MODEL)
    p.add_argument("-k", type=int, default=8)
    p.add_argument("--lang", default=None)
    p.add_argument("--num-ctx", type=int, default=8192)
    p.add_argument("--no-rag", action="store_true")
    p.add_argument("--plain", action="store_true",
                   help="raw text output, no panels or markdown rendering")
    args = p.parse_args()

    sess = Session(Settings(
        rag_url=args.rag_url, ollama_url=args.ollama_url, model=args.model,
        k=args.k, lang=args.lang, num_ctx=args.num_ctx, no_rag=args.no_rag,
    ))

    plain = args.plain or not sys.stdout.isatty()
    console = Console(highlight=False, soft_wrap=False)

    # Stdin pipe → one-shot.
    if not sys.stdin.isatty() and not args.question:
        q = sys.stdin.read().strip()
        if q:
            run_turn(console, sess, q, plain=plain)
            return 0

    # CLI args → one-shot.
    if args.question:
        run_turn(console, sess, " ".join(args.question), plain=plain)
        return 0

    # Otherwise → interactive REPL.
    return repl(console, sess)


if __name__ == "__main__":
    sys.exit(main())
