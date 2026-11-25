"""Test harness for the AccuracyKeyboard prompt.

  python3 check.py "我昨天不去学校"            check one or more messages
  python3 check.py --file tests.txt            check a test file, write results.html
  python3 check.py --model claude-sonnet-5-5 --file tests.txt   compare models

Uses the same prompt (Keyboard/prompt.md), JSON shape and guardrail as the
iPhone keyboard. The API key comes from ANTHROPIC_API_KEY, or else from
Keyboard/Secrets.swift, so you only have to paste it in one place.
"""

import argparse
import difflib
import html
import json
import os
import re
import sys
import time
from pathlib import Path

import anthropic

HERE = Path(__file__).parent
PROMPT_FILE = HERE / "Keyboard" / "prompt.md"
SECRETS_FILE = HERE / "Keyboard" / "Secrets.swift"

# Same schema as ClaudeClient.swift. Structured outputs make the API
# guarantee the reply is JSON in exactly this shape.
SCHEMA = {
    "type": "object",
    "properties": {
        "verdict": {"type": "string", "enum": ["natural", "not_natural", "error"]},
        "corrected": {"type": "string"},
        "changes": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "from": {"type": "string"},
                    "to": {"type": "string"},
                    "reason": {"type": "string"},
                },
                "required": ["from", "to", "reason"],
                "additionalProperties": False,
            },
        },
        "native_version": {"type": "string"},
    },
    "required": ["verdict", "corrected", "changes", "native_version"],
    "additionalProperties": False,
}


def load_api_key():
    if os.environ.get("ANTHROPIC_API_KEY"):
        return os.environ["ANTHROPIC_API_KEY"]
    if SECRETS_FILE.exists():
        match = re.search(r'anthropicAPIKey\s*=\s*"([^"]+)"', SECRETS_FILE.read_text())
        if match and "PASTE" not in match.group(1):
            return match.group(1)
    sys.exit("No API key. Paste it into Keyboard/Secrets.swift (or set ANTHROPIC_API_KEY).")


def check(client, model, effort, message):
    """Ask Claude about one message. Returns the parsed JSON dict."""
    response = client.messages.create(
        model=model,
        max_tokens=4000,
        system=PROMPT_FILE.read_text(encoding="utf-8"),
        messages=[{"role": "user", "content": message}],
        output_config={"effort": effort, "format": {"type": "json_schema", "schema": SCHEMA}},
    )
    if response.stop_reason == "refusal":
        raise RuntimeError("model declined to check this message")
    if response.stop_reason == "max_tokens":
        raise RuntimeError("reply was cut off")
    text = next(block.text for block in response.content if block.type == "text")
    result = json.loads(text)

    # The guardrail (same as the keyboard): natural verdict or no actual
    # change means ✓ with no changes, whatever else the model said.
    if result["verdict"] == "natural" or result["corrected"] == message:
        result.update(verdict="natural", corrected=message, changes=[])
    return result


def diff(original, corrected):
    """Character diff -> list of (kind, text), kind in same/removed/added.
    Python's version of Diff.swift (a different algorithm, same idea)."""
    out = []
    matcher = difflib.SequenceMatcher(None, original, corrected, autojunk=False)
    for op, a1, a2, b1, b2 in matcher.get_opcodes():
        if op == "equal":
            out.append(("same", original[a1:a2]))
        if op in ("delete", "replace"):
            out.append(("removed", original[a1:a2]))
        if op in ("insert", "replace"):
            out.append(("added", corrected[b1:b2]))
    return out


def terminal_diff(original, corrected):
    colors = {"same": "", "removed": "\033[9;31m", "added": "\033[32m"}  # 9 = strikethrough
    return "".join(f"{colors[k]}{t}\033[0m" if colors[k] else t for k, t in diff(original, corrected))


def read_tests(path):
    """Lines look like `message | natural` or `message | fix`. # starts a comment."""
    tests = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        message, _, label = line.rpartition("|")
        if not message:  # no label
            message, label = label, ""
        tests.append((message.strip(), label.strip().lower()))
    return tests


def outcome(label, verdict):
    """Compare what we expected with what the model did."""
    if label == "natural":
        return "ok" if verdict == "natural" else "FALSE ALARM"  # the worst kind of mistake
    if label == "fix":
        return "ok" if verdict != "natural" else "MISSED"
    return ""


LABELS = {"natural": "✓ natural", "not_natural": "不太自然", "error": "有错"}


def write_html(rows, model, path):
    def diff_html(original, corrected):
        tags = {"same": "{}", "removed": "<del>{}</del>", "added": "<ins>{}</ins>"}
        return "".join(tags[k].format(html.escape(t)) for k, t in diff(original, corrected))

    cards = []
    for r in rows:
        if "error_text" in r:
            body = f'<p class="err">{html.escape(r["error_text"])}</p>'
        else:
            res = r["result"]
            changes = "".join(
                f'<li><b>{html.escape(c["from"] or "—")} → {html.escape(c["to"] or "—")}</b> '
                f'{html.escape(c["reason"])}</li>'
                for c in res["changes"]
            )
            native = ""
            if res["native_version"] and res["native_version"] != res["corrected"]:
                native = f'<p class="native">Native: {html.escape(res["native_version"])}</p>'
            body = (
                f'<p class="msg">{diff_html(r["message"], res["corrected"])}</p>'
                f'<ul>{changes}</ul>{native}'
            )
        badge = f'<span class="badge {r["verdict"]}">{LABELS.get(r["verdict"], "error")}</span>'
        flag = f'<span class="flag">{r["outcome"]}</span>' if r["outcome"] not in ("", "ok") else ""
        expected = f'<span class="expected">expected: {r["label"]}</span>' if r["label"] else ""
        cards.append(f'<div class="card">{badge}{flag}{expected}{body}</div>')

    labeled = [r for r in rows if r["outcome"]]
    passed = sum(r["outcome"] == "ok" for r in labeled)
    false_alarms = sum(r["outcome"] == "FALSE ALARM" for r in labeled)
    missed = sum(r["outcome"] == "MISSED" for r in labeled)
    summary = (
        f"{passed}/{len(labeled)} as expected · {false_alarms} false alarms · {missed} missed"
        if labeled else f"{len(rows)} messages"
    )

    path.write_text(f"""<!doctype html>
<html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Check results</title>
<style>
  :root {{ color-scheme: light dark; --bg:#fafafa; --card:#fff; --text:#1d1d1f; --muted:#6e6e73; --line:#e5e5ea; }}
  @media (prefers-color-scheme: dark) {{ :root {{ --bg:#111; --card:#1c1c1e; --text:#f2f2f7; --muted:#98989d; --line:#2c2c2e; }} }}
  body {{ background:var(--bg); color:var(--text); font:16px -apple-system, "PingFang SC", sans-serif; max-width:760px; margin:0 auto; padding:24px 16px; }}
  h1 {{ font-size:20px; margin:0 0 4px; }} .sub {{ color:var(--muted); margin:0 0 20px; }}
  .card {{ background:var(--card); border:1px solid var(--line); border-radius:12px; padding:14px 16px; margin-bottom:12px; }}
  .msg {{ font-size:22px; margin:8px 0; }}
  del {{ color:#e5484d; }} ins {{ color:#30a46c; text-decoration:none; font-weight:600; }}
  ul {{ margin:6px 0; padding-left:20px; color:var(--muted); }} li b {{ color:var(--text); font-weight:600; }}
  .native {{ color:var(--muted); font-size:14px; margin:6px 0 0; }}
  .badge {{ font-size:13px; font-weight:600; padding:2px 8px; border-radius:6px; }}
  .natural {{ background:#30a46c22; color:#30a46c; }} .not_natural {{ background:#f5a52422; color:#d18b00; }}
  .error, .failed {{ background:#e5484d22; color:#e5484d; }}
  .flag {{ margin-left:8px; font-size:13px; font-weight:700; color:#e5484d; }}
  .expected {{ float:right; font-size:13px; color:var(--muted); }}
  .err {{ color:#e5484d; }}
</style></head><body>
<h1>Check results</h1>
<p class="sub">{html.escape(model)} · {summary}</p>
{''.join(cards)}
</body></html>
""", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Check Mandarin messages with the AccuracyKeyboard prompt.")
    parser.add_argument("messages", nargs="*", help="message(s) to check")
    parser.add_argument("--file", help="test file: one `message | natural|fix` per line")
    parser.add_argument("--model", default="claude-haiku-5-5")
    parser.add_argument("--effort", default="medium", choices=["low", "medium", "high"])  # same as the keyboard
    parser.add_argument("--out", default="results.html")
    args = parser.parse_args()

    tests = [(m, "") for m in args.messages]
    if args.file:
        tests += read_tests(args.file)
    if not tests:
        parser.error("give a message or --file tests.txt")

    client = anthropic.Anthropic(api_key=load_api_key())
    rows = []
    for message, label in tests:
        start = time.time()
        try:
            result = check(client, args.model, args.effort, message)
        except (anthropic.APIError, RuntimeError) as e:
            print(f"✗ {message}\n    {e}\n")
            rows.append({"message": message, "label": label, "verdict": "failed",
                         "outcome": "", "error_text": str(e)})
            if isinstance(e, (anthropic.AuthenticationError, anthropic.PermissionDeniedError)):
                sys.exit("Stopping: check your API key.")
            continue
        seconds = time.time() - start
        verdict = result["verdict"]
        out = outcome(label, verdict)
        rows.append({"message": message, "label": label, "verdict": verdict, "outcome": out, "result": result})

        flag = f"   ← {out}" if out not in ("", "ok") else ""
        print(f"{LABELS[verdict]}  ({seconds:.1f}s){flag}")
        print(f"    {terminal_diff(message, result['corrected'])}")
        for c in result["changes"]:
            print(f"    {c['from'] or '—'} → {c['to'] or '—'}: {c['reason']}")
        if result["native_version"] and result["native_version"] != result["corrected"]:
            print(f"    native: {result['native_version']}")
        print()

    if args.file:
        out_path = HERE / args.out
        write_html(rows, args.model, out_path)
        labeled = [r for r in rows if r["outcome"]]
        if labeled:
            passed = sum(r["outcome"] == "ok" for r in labeled)
            print(f"{passed}/{len(labeled)} as expected")
        print(f"Open the red/green view:  open {out_path.name}")


if __name__ == "__main__":
    main()
