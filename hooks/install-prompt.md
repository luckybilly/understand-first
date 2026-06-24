# Understand First — Install Prompt

Copy the prompt below into Claude Code. The AI will handle the full installation automatically.

---

```text
Install the "Understand First" hook for Claude Code. Follow these steps exactly:

## Step 1: Fetch the protocol

Use WebFetch to download the protocol from:
https://raw.githubusercontent.com/luckybilly/understand-first/main/CLAUDE.md

If the fetch fails, ask me to provide the protocol content manually.

## Step 2: Write the hook script

Write the following content to ~/.claude/hooks/understand-first-hook.sh (create the hooks/ directory if it doesn't exist):

- Line 1: #!/bin/sh
- Line 2: # Understand First — Claude Code Hook
- Line 3: (blank)
- Line 4: PROTOCOL=$(cat << 'PROTOCOL_EOF'
- Lines 5+: The enforcement preamble followed by the full protocol content from Step 1
- Then: PROTOCOL_EOF
- Then: )
- Then: (blank line)
- Then: printf '%s\n' "$PROTOCOL" | python3 -c "
- Then: import sys, json
- Then: content = sys.stdin.read()
- Then: payload = {
- Then:     'hookSpecificOutput': {
- Then:         'hookEventName': 'UserPromptSubmit',
- Then:         'additionalContext': content
- Then:     }
- Then: }
- Then: sys.stdout.write(json.dumps(payload, ensure_ascii=False))
- Then: "

The enforcement preamble is:

[IMPORTANT — Understand First Protocol Enforcement]

You MUST follow this protocol on EVERY user input. No exceptions. Skipping the understanding step is a protocol violation.

IMPORTANT: Before writing, replace all single quotes (') in the protocol content AND the preamble with the Unicode modifier letter apostrophe ʼ (U+02BC). This is required for macOS bash 3.2 compatibility. The JSON/python code at the bottom must keep its original single quotes — only apply the replacement to the preamble and protocol content inside the heredoc.

After writing, run: chmod +x ~/.claude/hooks/understand-first-hook.sh

## Step 3: Update settings.json

Read ~/.claude/settings.json. Add a UserPromptSubmit hook entry (if not already present) that runs:
  sh ~/.claude/hooks/understand-first-hook.sh

The entry should be added to hooks.UserPromptSubmit as:
{
  "matcher": "",
  "hooks": [{"type": "command", "command": "sh ~/.claude/hooks/understand-first-hook.sh"}]
}

If settings.json doesn't exist, create it with {}. Back up the original as settings.json.bak before modifying.

## Step 4: Write anchor to ~/.claude/CLAUDE.md

Check if ~/.claude/CLAUDE.md exists and contains "Understand First". If not:
- If the file exists: append a newline and this line:
  Always follow the "Understand First" protocol injected by the UserPromptSubmit hook — show your understanding before executing, every turn, without exception.
- If the file doesn't exist: create it with just that line.

## Step 5: Verify

Run: sh -n ~/.claude/hooks/understand-first-hook.sh
If syntax check fails, report the error and ask me what to do.

Then run the hook and verify it produces valid JSON output.

## Step 6: Done

Tell me the installation is complete and that I need to restart Claude Code to activate.
```
