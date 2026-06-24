# Understand First — 安装

将 "Understand First" hook 安装到当前 Claude Code 环境中——跨平台（Windows / macOS / Linux）。

这是 agent 驱动的安装器，安装结果与 `hooks/install.sh` 等价：相同的强制前缀 + 完整协议作为 `additionalContext` 在每次用户输入时注入。当 `curl | sh` 无法运行时（尤其是原生 Windows），或希望由 agent 驱动安装时使用。

## 目标

安装后，每次用户提交提示词时，Claude Code 必须在执行任何操作之前先展示它对请求的理解。通过注册一个 `UserPromptSubmit` hook 来实现，该 hook 将协议作为 `additionalContext` 注入。

## 操作规则

- 不要使用 `sudo`。
- 不要未经明确许可就覆盖用户已有文件——改为追加或合并。
- 所有操作必须幂等——安装两次和安装一次的结果应相同。
- 修改文件前先备份（保存为 `<文件名>.bak`），并通过临时文件 + 原子 rename 写入（不要原地覆盖——写入中断会损坏文件）。
- 写入任何位置前（尤其是写入 `settings.json`）都把路径解析为**绝对路径**。**绝不**把 `~`、`$HOME`、`%USERPROFILE%` 占位符写进注册命令——Claude Code 在各平台上对这些占位符的展开并不可靠。
- JSON 只能通过 JSON 库序列化（`json.dumps` / `ConvertTo-Json` / `jq`）。**绝不手搓 JSON**——协议正文含引号、换行、unicode，会打断朴素的字符串拼接。
- hook 优先用 Python（跨平台、`json.dumps` 保证 JSON 正确、`Path.home()` 在所有系统上解析用户目录）。仅当无 Python 时才回退到 PowerShell（Windows）或 POSIX `sh` + `jq`（Unix）。

## 成功标准

安装后以下条件必须全部满足：

1. `~/.claude/hooks/understand-first-hook.py` 存在，且同目录有 `~/.claude/hooks/understand-first-protocol.txt`（原始前缀 + 协议，UTF-8）。
2. 执行**注册的命令**会向 stdout 输出有效 JSON：
   ```json
   {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "<前缀 + 协议>"}}
   ```
3. `additionalContext` 以强制前缀开头，并包含完整协议（非空，且包含 `Understand First`）。
4. `~/.claude/settings.json` 有一个 `UserPromptSubmit` 条目，其 `command` 以绝对路径调用 hook。
5. `~/.claude/CLAUDE.md` 包含 Understand First 锚点行。

## 步骤

### 1. 检测平台与解释器

- 判断操作系统（Windows / macOS / Linux）。
- 按以下顺序探测 Python 解释器，记录**第一个能运行并输出版本**的：`py -3`，然后 `python3`，然后 `python`。把调用前缀（如 `py -3`、`python3`、`python`）记为 `PY`。
- 解析 hooks 目录：`~/.claude/hooks`（用 Python 的 `Path.home()` 等价方式——不要假设字符串里的 `~`）。
- 若**完全没有 Python**：走下方的"兜底（无 Python）"路径。若兜底运行时也不可用（Windows 无 PowerShell、Unix 无 `jq`），停下并请用户安装 Python 3。

### 2. 获取协议

按以下顺序解析协议正文（与 `install.sh` 对齐）：

1. **优先离线**——若当前工作目录下存在 `./CLAUDE.md` 且其首行恰为 `# Understand First`，则本地读取，免网络。（仅在本仓库克隆内运行时适用；H1 检查可防止注入其他项目的 CLAUDE.md。）
2. 否则用 WebFetch：`https://raw.githubusercontent.com/luckybilly/understand-first/main/zh-CN/CLAUDE.md`
3. 若获取失败，请用户手动粘贴协议内容。不要用空协议正文继续。

### 3. 创建 hook（两个自包含文件）

按需创建 `~/.claude/hooks/`，然后写入**两个**文件：

**`understand-first-protocol.txt`**——原始注入内容，UTF-8，无需转义：

```
[重要 · Understand First 协议强制执行]

每轮用户输入都必须先展示理解、再执行——无例外。跳过理解步骤即视为协议违规。
```

……后接一个空行，再接第 2 步获取的完整协议正文。即文件内容 = `前缀 + "\n\n" + 协议`。**不要**做 `'` → `ʼ` 撇号替换——那是 bash 3.2 heredoc bug 的权宜之计，对 Python hook 不适用；协议正文保持原样。

**`understand-first-hook.py`**——逐字使用下方"参考实现"中的版本。它读取同目录 `.txt` 并通过 `json.dumps` 输出，转义永远正确。

Unix 上对 hook 执行 `chmod +x`（可选——注册命令已显式调用解释器）。

### 4. 在 settings.json 注册 hook

运行下方的**参考合并脚本**（确定性：精确幂等检查、`.bak` 备份、原子 rename）。用探测到的解释器与 hook 绝对路径设置其 `cmd`：

- `cmd = '<PY> "<绝对路径>/understand-first-hook.py"'`
- Windows 上，绝对路径用**正斜杠**（Python 接受），这样 JSON 无需反斜杠转义。
- 仅当某条目的 `matcher` 为 `""` 或 `null` **且**其内层 `hooks[]` 中某条 `command` 含 `understand-first` 时，才算"已安装"。若已存在，不做任何改动。

若 `settings.json` 不存在，创建为 `{}`。

### 5. 写入锚点到 CLAUDE.md

检查 `~/.claude/CLAUDE.md` 是否含字符串 `Understand First`。若无：
- 文件已存在 → 追加锚点行。
- 文件不存在 → 创建文件并写入锚点行。

锚点行：
```
Always follow the "Understand First" protocol injected by the UserPromptSubmit hook — show your understanding before executing, every turn, without exception.
```

## 验证（必须实际执行——不能只看文件）

1. 运行第 4 步注册的**确切** `command`，捕获 stdout，并 `json.loads` 解析。断言 `hookSpecificOutput.additionalContext` 非空且含 `Understand First`。**若输出不是有效 JSON 或 `additionalContext` 为空，这是硬失败——不得宣称成功。** 报告原始输出并先修复再完成。
2. 重新读取 `settings.json`，确认 `UserPromptSubmit` 条目存在且 command 匹配。
3. 确认 `~/.claude/CLAUDE.md` 含锚点行。

若有问题，报告错误并问我怎么处理。

## 完成汇报格式

汇报：
- 检测到的平台（操作系统 + 可用运行时 + 选定的 Python 调用方式）
- 选用的 hook 语言/运行时
- 两个 hook 文件的路径
- 注册到 settings.json 的确切 `command`
- 每条成功标准：通过 / 未通过
- 提醒需要重启 Claude Code 才能生效

## 参考实现

### `understand-first-hook.py`（逐字写入）

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

### settings.json 合并脚本（用探测到的 Python 运行）

替换其中的 `<PY>` 与 hook 绝对路径。幂等、备份到 `.bak`、原子写入。

```python
import json
import os
import shutil

settings = os.path.join(os.path.expanduser("~"), ".claude", "settings.json")
hook_py = os.path.join(os.path.expanduser("~"), ".claude", "hooks", "understand-first-hook.py")
# cmd 在 Windows 上用正斜杠，避免 JSON 反斜杠转义：
hook_py_fwd = hook_py.replace("\\", "/")
cmd = '<PY> "%s"' % hook_py_fwd   # 例如 'python3 "..."' 或 'python "..."' 或 'py -3 "..."'

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

## 兜底（无 Python）

仅当第 1 步找不到 Python 时使用。协议正文仍存于 `understand-first-protocol.txt`（同目录、同内容）；仅 hook 与其 command 不同。

**Windows — PowerShell**（`understand-first-hook.ps1`）：

```powershell
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$protocol = Get-Content -Raw (Join-Path $here 'understand-first-protocol.txt')
@{ hookSpecificOutput = @{ hookEventName = 'UserPromptSubmit'; additionalContext = $protocol } } |
    ConvertTo-Json -Compress -Depth 5
```

注册命令（绝对路径，注意 `-ExecutionPolicy Bypass` 以绕过执行策略拦截）：

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<绝对路径>/understand-first-hook.ps1"
```

**Unix — POSIX sh + jq**（`understand-first-hook.sh`）：

```sh
#!/bin/sh
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec jq -Rs '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.}}' \
  "$DIR/understand-first-protocol.txt"
```

注册命令：`sh "<绝对路径>/understand-first-hook.sh"`（需 PATH 上有 `jq`）。

若 Python 与对应兜底运行时都不可用，停下并请用户安装 Python 3——不要尝试手搓 JSON hook。

## 立即执行
