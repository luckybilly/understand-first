#!/bin/sh
# Understand First Hook Installer
# One-line install: curl -fsSL https://raw.githubusercontent.com/luckybilly/understand-first/main/hooks/install.sh | sh
#
# Fetches the Understand First protocol from CLAUDE.md (single source of truth)
# and bakes it into a self-contained, human-readable hook script. The hook
# injects the protocol via additionalContext on every user input.
#
# Requires: curl, python3
#
# Protocol resolution (no flag needed for a normal clone — ../CLAUDE.md is
# auto-detected next to this script):
#   UNDERSTAND_FIRST_PROTOCOL_FILE=<path>  force a specific CLAUDE.md
#   UNDERSTAND_FIRST_PROTOCOL_URL=<url>    fetch from a custom URL (pinned tag/fork)

set -e

HOOK_DIR="$HOME/.claude/hooks"
HOOK_DST="$HOOK_DIR/understand-first-hook.sh"
SETTINGS="$HOME/.claude/settings.json"

PROTOCOL_URL="${UNDERSTAND_FIRST_PROTOCOL_URL:-https://raw.githubusercontent.com/luckybilly/understand-first/main/CLAUDE.md}"

# --- Preflight ---

for dep in curl python3; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "Error: $dep is required." >&2
        case "$dep" in
            curl)    echo "  Install curl via your package manager." >&2 ;;
            python3) echo "  macOS: brew install python3 | Linux: apt/yum install python3" >&2 ;;
        esac
        exit 1
    fi
done

# --- Locate the protocol (CLAUDE.md is the single source of truth) ---
#
# Resolution order:
#   1. UNDERSTAND_FIRST_PROTOCOL_FILE (explicit override; trusted as-is)
#   2. CLAUDE.md next to this script (../CLAUDE.md) — local/cloned installs, offline
#      (guarded by a signature check so a foreign CLAUDE.md is never injected)
#   3. fetch the canonical copy from GitHub (for `curl | sh` once published)
#
# Resolve the script's own directory. Empty when this can't be determined
# (e.g. piped via `curl | sh`, where $0 is just "sh").
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || SCRIPT_DIR=""

looks_like_our_protocol() {
    # Our CLAUDE.md always starts with "# Understand First" as its H1.
    [ -f "$1" ] || return 1
    head -n 1 "$1" 2>/dev/null | grep -q '^# Understand First'
}

PROTOCOL=""
if [ -n "${UNDERSTAND_FIRST_PROTOCOL_FILE:-}" ]; then
    [ -f "$UNDERSTAND_FIRST_PROTOCOL_FILE" ] || {
        echo "Error: UNDERSTAND_FIRST_PROTOCOL_FILE not found: $UNDERSTAND_FIRST_PROTOCOL_FILE" >&2
        exit 1
    }
    PROTOCOL=$(cat "$UNDERSTAND_FIRST_PROTOCOL_FILE")
    echo "✓ Using local protocol: $UNDERSTAND_FIRST_PROTOCOL_FILE"
elif [ -n "$SCRIPT_DIR" ] && looks_like_our_protocol "$SCRIPT_DIR/../CLAUDE.md"; then
    PROTOCOL=$(cat "$SCRIPT_DIR/../CLAUDE.md")
    echo "✓ Using protocol from repo (offline): $SCRIPT_DIR/../CLAUDE.md"
else
    echo "Fetching Understand First protocol from $PROTOCOL_URL ..."
    PROTOCOL=$(curl -fsSL "$PROTOCOL_URL") || {
        echo "Error: failed to fetch protocol from $PROTOCOL_URL" >&2
        echo "  Tip: run from a clone of the repo, or set UNDERSTAND_FIRST_PROTOCOL_FILE." >&2
        exit 1
    }
    echo "✓ Protocol fetched"
fi

if [ -z "$PROTOCOL" ]; then
    echo "Error: protocol content is empty." >&2
    exit 1
fi

# --- Create the self-contained hook script (protocol embedded via heredoc) ---
# Single quotes (apostrophes) in protocol content break bash 3.2's parser when
# the heredoc is nested inside $(). Even with single-quoted delimiters, bash
# 3.2 matches apostrophes while looking for the closing ), causing syntax
# errors on content like "you're". We replace them with Unicode U+02BC.

mkdir -p "$HOOK_DIR"

# Enforcement preamble — prepended ONLY to the hook's injected context, never
# to CLAUDE.md itself. additionalContext arrives as user-turn content (lower
# authority than system context), so the hook channel needs this compliance
# boost to counter the model's urge to skip the understanding step — especially
# on simple inputs ("No exceptions"). CLAUDE.md is a system-context channel and
# does not need it, so we keep that file clean and add the preamble here.
ENFORCEMENT='[IMPORTANT — Understand First Protocol Enforcement]

You MUST follow this protocol on EVERY user input. No exceptions. Skipping the understanding step is a protocol violation.'

# Strip single quotes to avoid bash 3.2 heredoc-in-$() parser bug.
# bash 3.2 matches apostrophes inside single-quoted heredocs when scanning
# for the closing ) of $(), causing syntax errors on content like "you're".
# Replace with Unicode modifier letter apostrophe (U+02BC) — visually
# identical and fully readable by the LLM.
PROTOCOL_CLEAN=$(printf '%s' "$PROTOCOL" | sed "s/'/ʼ/g")

cat > "$HOOK_DST" << 'HOOK_HEAD'
#!/bin/sh
# Understand First — Claude Code Hook (self-contained)
# Understand First protocol embedded below; injected via additionalContext on every prompt.

PROTOCOL=$(cat << 'PROTOCOL_EOF'
HOOK_HEAD

printf '%s\n\n%s\n' "$ENFORCEMENT" "$PROTOCOL_CLEAN" >> "$HOOK_DST"

cat >> "$HOOK_DST" << 'HOOK_TAIL'
PROTOCOL_EOF
)

printf '%s\n' "$PROTOCOL" | python3 -c "
import sys, json
content = sys.stdin.read()
payload = {
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': content
    }
}
sys.stdout.write(json.dumps(payload, ensure_ascii=False))
"
HOOK_TAIL

chmod +x "$HOOK_DST"
echo "✓ Hook script installed to $HOOK_DST"

# --- Configure settings.json ---

if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
    echo "✓ Created $SETTINGS"
fi

HOOK_CMD="sh $HOOK_DST"

# Merge the hook entry into settings.json using python3 (no jq dependency).
# Mirrors the original jq behavior: a match counts only when the entry's
# matcher is "" or null, inspecting its inner hooks[] for the command.
# Prints EXISTS (no-op) or ADDED (wrote + backed up); anything else is an error.
RESULT=$(python3 - "$SETTINGS" "$HOOK_CMD" 2>&1 << 'PYEOF'
import json, os, shutil, sys
settings_path, cmd = sys.argv[1], sys.argv[2]

with open(settings_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

hooks = data.get('hooks')
if not isinstance(hooks, dict):
    hooks = {}
ups = hooks.get('UserPromptSubmit')
if not isinstance(ups, list):
    ups = []

already = False
for entry in ups:
    if entry.get('matcher', None) in ("", None):
        for h in entry.get('hooks', []):
            if h.get('command') == cmd:
                already = True
                break
        if already:
            break

if already:
    print("EXISTS")
else:
    shutil.copyfile(settings_path, settings_path + ".bak")
    hooks = data.setdefault('hooks', {})
    if not isinstance(hooks, dict):
        hooks = {}
        data['hooks'] = hooks
    ups = hooks.get('UserPromptSubmit')
    if not isinstance(ups, list):
        ups = []
        hooks['UserPromptSubmit'] = ups
    ups.append({
        "matcher": "",
        "hooks": [{
            "type": "command",
            "command": cmd
        }]
    })
    tmp = settings_path + ".tmp"
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write('\n')
    os.replace(tmp, settings_path)
    print("ADDED")
PYEOF
)

case "$RESULT" in
    EXISTS)
        echo "✓ Hook already configured in settings.json — no changes needed"
        ;;
    ADDED)
        echo "✓ Added Understand First hook to settings.json"
        echo "  Backup saved as $SETTINGS.bak"
        ;;
    *)
        echo "Error: failed to configure settings.json:" >&2
        echo "$RESULT" >&2
        exit 1
        ;;
esac

# --- Write anchor line to ~/.claude/CLAUDE.md ---
# CLAUDE.md is loaded at session start with high weight. A short anchor here
# primes the model to respect the hook-injected protocol, counteracting the
# first-turn attention dip when the system prompt is long.
#
# Behavior:
#   - File doesn't exist  → create with anchor
#   - File exists, anchor absent → append anchor
#   - File exists, anchor already present → skip (idempotent)

GLOBAL_CLAUDE_MD="$HOME/.claude/CLAUDE.md"
ANCHOR='Always follow the "Understand First" protocol injected by the UserPromptSubmit hook — show your understanding before executing, every turn, without exception.'

if [ -f "$GLOBAL_CLAUDE_MD" ] && grep -qF 'Understand First' "$GLOBAL_CLAUDE_MD"; then
    echo "✓ CLAUDE.md anchor already present — no changes needed"
else
    if [ -f "$GLOBAL_CLAUDE_MD" ]; then
        printf '\n%s\n' "$ANCHOR" >> "$GLOBAL_CLAUDE_MD"
        echo "✓ Appended Understand First anchor to $GLOBAL_CLAUDE_MD"
    else
        printf '%s\n' "$ANCHOR" > "$GLOBAL_CLAUDE_MD"
        echo "✓ Created $GLOBAL_CLAUDE_MD with Understand First anchor"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Understand First installed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Hook:     protocol injected on every user input"
echo "  CLAUDE.md: short anchor primes the model at session start"
echo ""
echo "Restart Claude Code to activate."
