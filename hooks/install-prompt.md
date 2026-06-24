# Understand First — Install

Install the "Understand First" hook into the current Claude Code environment — cross-platform (Windows / macOS / Linux).

This is the agent-driven installer. Its installed result is equivalent to `hooks/install.sh`: the same enforcement preamble + full protocol injected as `additionalContext` on every user input. Use it where `curl | sh` cannot run (notably native Windows), or whenever an agent-driven install is preferred.

## Goal

After installation, every time the user submits a prompt, Claude Code must display its understanding of the request BEFORE taking any action. This is achieved by registering a `UserPromptSubmit` hook that injects the protocol as `additionalContext`.

## Operating Rules

- Do NOT use `sudo`.
- Do NOT overwrite existing user files without explicit permission — append or merge instead.
- All operations must be idempotent — running the install twice must equal running it once.
- Back up any file before modifying it (save as `<filename>.bak`), then write via temp-file + atomic rename (never overwrite in place — an interrupted write corrupts the file).
- Resolve every path to an **absolute** path before writing it anywhere (especially into `settings.json`). Never write `~`, `$HOME`, or `%USERPROFILE%` placeholders into the registered command — Claude Code does not expand them reliably across platforms.
- Serialize JSON only through a JSON library (`json.dumps` / `ConvertTo-Json` / `jq`). **Never hand-build JSON** from the protocol text — it contains quotes, newlines, and unicode that will break naive string concatenation.
- Prefer Python for the hook (cross-platform, guaranteed-correct JSON via `json.dumps`, and `Path.home()` resolves the profile dir on every OS). Fall back to PowerShell (Windows) or POSIX `sh` + `jq` (Unix) only when no Python is available.

## Success Criteria

All of the following must be true after installation:

1. `~/.claude/hooks/understand-first-hook.py` exists, alongside `~/.claude/hooks/understand-first-protocol.txt` (the raw preamble + protocol, UTF-8).
2. Executing the **registered command** outputs valid JSON to stdout:
   ```json
   {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "<preamble + protocol>"}}
   ```
3. `additionalContext` starts with the enforcement preamble and contains the full protocol (non-empty, contains `Understand First`).
4. `~/.claude/settings.json` has a `UserPromptSubmit` entry whose `command` invokes the hook by absolute path.
5. `~/.claude/CLAUDE.md` contains the Understand First anchor line.

## Steps

### 1. Detect platform & interpreter

- Determine OS (Windows / macOS / Linux).
- Probe for a Python interpreter in this order; record the **first that runs** and prints a version: `py -3`, then `python3`, then `python`. Store the invocation prefix (e.g. `py -3`, `python3`, `python`) as `PY`.
- Resolve the hooks directory: `~/.claude/hooks` (use the Python `Path.home()` equivalent — do NOT assume `~` in strings).
- If **no Python at all** is found: use the **Fallback (no Python)** path below. If the fallback runtime is also unavailable (no PowerShell on Windows, no `jq` on Unix), STOP and ask the user to install Python 3.

### 2. Fetch the protocol

Resolve the protocol text in this order (mirrors `install.sh`):

1. **Offline first** — if a file `./CLAUDE.md` in the current working directory exists and its first line is exactly `# Understand First`, read it locally. No network needed. (This only applies when running inside a clone of this repo; the H1 check prevents injecting some other project's CLAUDE.md.)
2. Otherwise WebFetch: `https://raw.githubusercontent.com/luckybilly/understand-first/main/CLAUDE.md`
3. If the fetch fails, ask the user to paste the protocol content manually. Do not proceed with empty protocol text.

### 3. Create the hook (two self-contained files)

Create `~/.claude/hooks/` if needed, then write **two** files:

**`understand-first-protocol.txt`** — the raw injected context, UTF-8, no escaping:

```
[IMPORTANT — Understand First Protocol Enforcement]

You MUST follow this protocol on EVERY user input. No exceptions. Skipping the understanding step is a protocol violation.
```

…followed by a blank line, then the full protocol text fetched in step 2. So the file content equals `PREAMBLE + "\n\n" + PROTOCOL`. Do **not** apply the `'` → `ʼ` apostrophe substitution — that was a workaround for a bash 3.2 heredoc bug that does not apply to a Python hook; keep the protocol text verbatim.

**`understand-first-hook.py`** — use the reference implementation under "Reference Implementation" below verbatim. It reads the sibling `.txt` and emits it via `json.dumps`, so all escaping is always correct.

On Unix, `chmod +x` the hook (optional — the registered command invokes the interpreter explicitly).

### 4. Register the hook in settings.json

Run the **Reference merge script** below (deterministic: precise idempotency check, `.bak` backup, atomic rename). Set its `cmd` from the detected interpreter and the absolute hook path:

- `cmd = '<PY> "<ABSOLUTE_PATH>/understand-first-hook.py"'`
- On Windows, use **forward slashes** in the absolute path (Python accepts them) so the JSON needs no backslash escaping.
- An entry counts as "already installed" only when its `matcher` is `""` or `null` **and** one of its inner `hooks[]` has a `command` containing `understand-first`. If already present, make no changes.

If `settings.json` does not exist, create it as `{}`.

### 5. Write anchor to CLAUDE.md

Check `~/.claude/CLAUDE.md` for the string `Understand First`. If absent:
- File exists → append the anchor line.
- File missing → create it with the anchor line.

Anchor line:
```
Always follow the "Understand First" protocol injected by the UserPromptSubmit hook — show your understanding before executing, every turn, without exception.
```

## Verification (must actually execute — not just inspect files)

1. Run the **exact** `command` registered in step 4, capture stdout, and `json.loads` it. Assert `hookSpecificOutput.additionalContext` is non-empty and contains `Understand First`. **If the output is not valid JSON or `additionalContext` is empty, this is a hard failure — do NOT declare success.** Report the raw output and fix it before finishing.
2. Re-read `settings.json` and confirm the `UserPromptSubmit` entry exists with the matching command.
3. Confirm `~/.claude/CLAUDE.md` contains the anchor line.

If anything fails, report the error and ask what to do.

## Final Response Format

Report:
- Platform detected (OS + available runtimes, + chosen Python invocation)
- Hook language/runtime chosen
- Paths of the two hook files
- The exact `command` registered in settings.json
- Each success criterion: passed / failed
- Reminder to restart Claude Code to activate

## Reference Implementation

### `understand-first-hook.py` (write this verbatim)

```python
#!/usr/bin/env python3
"""Understand First — Claude Code UserPromptSubmit hook (self-contained).

Reads the protocol text from the sibling file understand-first-protocol.txt
and emits it as additionalContext. JSON is produced via json.dumps, so all
escaping (quotes, newlines, unicode) is always correct — never hand-built.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROTOCOL_FILE = os.path.join(HERE, "understand-first-protocol.txt")

try:
    with open(PROTOCOL_FILE, encoding="utf-8") as f:
        content = f.read()
except OSError as exc:
    sys.stderr.write(
        "understand-first-hook: cannot read %s: %s\n" % (PROTOCOL_FILE, exc)
    )
    content = ""

payload = {
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": content,
    }
}
sys.stdout.write(json.dumps(payload, ensure_ascii=False))
```

### Merge script for settings.json (run with the detected Python)

Substitute `<PY>` and the absolute hook path. It is idempotent, backs up to `.bak`, and writes atomically.

```python
import json
import os
import shutil

settings = os.path.join(os.path.expanduser("~"), ".claude", "settings.json")
hook_py = os.path.join(os.path.expanduser("~"), ".claude", "hooks", "understand-first-hook.py")
# cmd uses forward slashes on Windows to avoid JSON backslash escaping:
hook_py_fwd = hook_py.replace("\\", "/")
cmd = '<PY> "%s"' % hook_py_fwd   # e.g. 'python3 "..."' or 'python "..."' or 'py -3 "..."'

os.makedirs(os.path.dirname(settings), exist_ok=True)
if not os.path.isfile(settings):
    with open(settings, "w", encoding="utf-8") as f:
        f.write("{}")

with open(settings, encoding="utf-8") as f:
    data = json.load(f)

hooks = data.get("hooks")
if not isinstance(hooks, dict):
    hooks = {}
ups = hooks.get("UserPromptSubmit")
if not isinstance(ups, list):
    ups = []

already = False
for entry in ups:
    if entry.get("matcher", None) in ("", None):
        for h in entry.get("hooks", []):
            if "understand-first" in h.get("command", ""):
                already = True
                break
        if already:
            break

if already:
    print("EXISTS")
else:
    shutil.copyfile(settings, settings + ".bak")
    hooks = data.setdefault("hooks", {})
    ups = hooks.get("UserPromptSubmit")
    if not isinstance(ups, list):
        ups = []
        hooks["UserPromptSubmit"] = ups
    ups.append({"matcher": "", "hooks": [{"type": "command", "command": cmd}]})
    tmp = settings + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, settings)
    print("ADDED")
```

## Fallback (no Python)

Only when step 1 finds no Python. The protocol text is still stored in `understand-first-protocol.txt` (same content, same dir); only the hook and its command differ.

**Windows — PowerShell** (`understand-first-hook.ps1`):

```powershell
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$protocol = Get-Content -Raw (Join-Path $here 'understand-first-protocol.txt')
@{ hookSpecificOutput = @{ hookEventName = 'UserPromptSubmit'; additionalContext = $protocol } } |
    ConvertTo-Json -Compress -Depth 5
```

Registered command (absolute path, note `-ExecutionPolicy Bypass` to sidestep policy blocks):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<ABSOLUTE_PATH>/understand-first-hook.ps1"
```

**Unix — POSIX sh + jq** (`understand-first-hook.sh`):

```sh
#!/bin/sh
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec jq -Rs '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.}}' \
  "$DIR/understand-first-protocol.txt"
```

Registered command: `sh "<ABSOLUTE_PATH>/understand-first-hook.sh"` (requires `jq` on PATH).

If neither Python nor the applicable fallback runtime is available, stop and ask the user to install Python 3 — do not attempt a hand-built JSON hook.

## EXECUTE NOW
