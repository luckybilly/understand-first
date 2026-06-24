# Understand First — 安装提示词

将下面的提示词复制到 Claude Code 中，AI 会自动完成全部安装。

---

```text
帮我安装 "Understand First" hook。请严格按以下步骤执行：

## 第一步：获取协议

用 WebFetch 从以下地址下载协议内容：
https://raw.githubusercontent.com/luckybilly/understand-first/main/zh-CN/CLAUDE.md

如果获取失败，让我手动提供协议内容。

## 第二步：写 hook 脚本

将以下内容写入 ~/.claude/hooks/understand-first-hook.sh（如果 hooks/ 目录不存在则创建）：

- 第 1 行：#!/bin/sh
- 第 2 行：# Understand First — Claude Code Hook
- 第 3 行：（空行）
- 第 4 行：PROTOCOL=$(cat << 'PROTOCOL_EOF'
- 第 5 行起：执行指令前缀 + 第一步获取的完整协议内容
- 然后：PROTOCOL_EOF
- 然后：)
- 然后：（空行）
- 然后：printf '%s\n' "$PROTOCOL" | python3 -c "
- 然后：import sys, json
- 然后：content = sys.stdin.read()
- 然后：payload = {
- 然后：    'hookSpecificOutput': {
- 然后：        'hookEventName': 'UserPromptSubmit',
- 然后：        'additionalContext': content
- 然后：    }
- 然后：}
- 然后：sys.stdout.write(json.dumps(payload, ensure_ascii=False))
- 然后："

执行指令前缀内容如下：

[重要 · Understand First 协议强制执行]

每轮用户输入都必须先展示理解、再执行——无例外。跳过理解步骤即视为协议违规。

重要：写入前，将协议内容和执行指令前缀中的所有英文单引号（'）替换为 Unicode 修饰符右单引号 ʼ（U+02BC）。这是为了兼容 macOS bash 3.2。底部的 JSON/python 代码保持原始单引号不变——只替换 heredoc 内的前缀和协议内容中的单引号。

写入完成后执行：chmod +x ~/.claude/hooks/understand-first-hook.sh

## 第三步：更新 settings.json

读取 ~/.claude/settings.json，添加 UserPromptSubmit hook 条目（如果尚未存在），执行命令为：
  sh ~/.claude/hooks/understand-first-hook.sh

条目格式：
{
  "matcher": "",
  "hooks": [{"type": "command", "command": "sh ~/.claude/hooks/understand-first-hook.sh"}]
}

添加到 hooks.UserPromptSubmit 数组中。如果 settings.json 不存在，先创建为空 {}。修改前备份为 settings.json.bak。

## 第四步：写入锚点到 ~/.claude/CLAUDE.md

检查 ~/.claude/CLAUDE.md 是否存在且包含 "Understand First"。如果没有：
- 如果文件已存在：在末尾追加换行和这一行：
  Always follow the "Understand First" protocol injected by the UserPromptSubmit hook — show your understanding before executing, every turn, without exception.
- 如果文件不存在：创建文件，只写这一行。

## 第五步：验证

执行：sh -n ~/.claude/hooks/understand-first-hook.sh
如果语法检查失败，报告错误并问我怎么处理。

然后执行 hook 并验证输出是否为有效 JSON。

## 第六步：完成

告诉我安装完成，需要重启 Claude Code 才能生效。
```
