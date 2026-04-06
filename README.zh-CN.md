# Codex-Vault

> 给任何 LLM agent 加上持久记忆。
> 你的笔记，你的 git，你的数据。

## 问题

LLM agent 每次对话都从零开始。上次做的决策忘了，讨论过的方案忘了，知识永远无法积累。

## 方案

一个结构化的知识库 + 3 个 hook，让 agent 拥有跨 session 的记忆。支持 **Claude Code** 和 **Codex CLI**。纯 markdown + git，没有外部依赖。

## 核心用法

5 个动作，覆盖日常全部场景：

| 动作 | 怎么做 | 什么时候用 |
|------|--------|-----------|
| **设目标** | 编辑 `brain/North Star.md` | 首次使用，或方向调整时 |
| **随手记** | `/dump 内容` | 做了决策、有了想法、完成了什么 — 随时 dump |
| **查记忆** | `/recall 关键词` | 忘了之前的决策、想找历史笔记 |
| **吃内容** | `/ingest URL或文件` | 看到好文章、拿到新资料，结构化存入 |
| **收尾** | `/wrap-up` | session 结束前，检查质量、更新索引 |

> Codex CLI 用 `$dump`、`$recall`、`$ingest`、`$wrap-up`。

### 提示词模板

直接复制使用，替换 `<>` 里的内容：

**`/dump` — 随手记**
```
/dump 我们决定用 <方案A> 而不是 <方案B>，因为 <原因>
/dump <项目名> 完成了，关键成果：<成果描述>
/dump 今天发现一个规律：<规律描述>
/dump 记住：<任何你想让 agent 下次记得的事>
```

**`/recall` — 查记忆**
```
/recall <关键词>
/recall 我们之前怎么决定的 <某件事>
/recall <项目名> 的进展
```

**`/ingest` — 吃内容**
```
/ingest <URL>
/ingest sources/<文件名>.md
```

**`/wrap-up` — 收尾**
```
/wrap-up
```
> 不需要参数，agent 自动扫描本次 session 的变更。

日常最高频的就是 `/dump`。其他按需使用。

## 30 秒上手

```bash
# 在你的项目目录下：
npx @suwujs/codex-vault init
claude                                  # 或: codex
```

填好 `vault/brain/North Star.md`，开始对话。

<details>
<summary>其他安装方式：从源码安装</summary>

```bash
git clone https://github.com/sukbearai/codex-vault.git /tmp/codex-vault
bash /tmp/codex-vault/plugin/install.sh
```

> **独立模式**：在 codex-vault 仓库内运行 `install.sh`，以 `vault/` 为工作目录。
</details>

## 工作原理

```
你说话
  ↓
classify hook（分类：决策？进展？想法？）
  ↓
Agent 写笔记（按 instructions.md 规范）
  ↓
validate hook（检查：frontmatter？wikilinks？正确目录？）
  ↓
git commit（持久化）
  ↓
下次 session → session-start hook 注入上下文
```

三个 hook 驱动整个循环：

| Hook | 触发时机 | 做什么 |
|------|---------|--------|
| **session-start** | Agent 启动 | 注入 North Star 目标、近期 git 变更、活跃项目、vault 文件清单 |
| **classify-message** | 每条消息 | 检测决策、成果、项目更新 — 提示 agent 该归档到哪里 |
| **validate-write** | 写 `.md` 后 | 检查 frontmatter 和 wikilinks — 在落盘前纠错 |

## 支持的 Agent

| Agent | Hooks | Skills | 状态 |
|-------|-------|--------|------|
| Claude Code | `.claude/settings.json` 3 hooks | `/dump` `/recall` `/ingest` `/wrap-up` | 完整支持 |
| Codex CLI | `.codex/hooks.json` 3 hooks | `$dump` `$recall` `$ingest` `$wrap-up` | 完整支持 |
| 其他 | 写适配器（[指南](docs/adding-an-agent.md)） | 取决于 agent | 社区贡献 |

## Vault 结构

```
vault/
  Home.md                 入口 — 当前焦点、快速链接
  log.md                  操作日志（append-only）
  brain/
    North Star.md         目标和方向 — 每次 session 自动读取
    Memories.md           记忆索引
    Key Decisions.md      值得跨 session 记住的决策
    Patterns.md           反复出现的规律
  work/
    Index.md              所有工作笔记的索引
    active/               进行中的项目
    archive/              已完成的项目
  templates/              笔记模板
  thinking/               草稿区 — 想清楚后归档，然后删除
  sources/                原始资料 — 不可修改，agent 只读
  reference/              问答回写 — 有价值的综合分析
```

八个目录，五种笔记类型。

## 使用场景

详见 [docs/usage.md](docs/usage.md) — 7 个真实场景，从首次安装到项目完成，每一步都有输入和输出示例。

## 设计原则

1. **数据主权** — 你的 markdown，你的 git，你的机器。没有云端锁定。
2. **Agent 无关** — hook 是通用接口。一个 vault，多个 agent。
3. **默认极简** — 3 个 hook，~100 行指令。按需增加复杂度。
4. **图优先** — 目录按用途分组，`[[wikilinks]]` 按语义分组。链接是主要的组织工具。
5. **面向未来** — 即使模型有了内建记忆，vault 仍然有价值：可审计、可迁移、git 追踪的本地存储。

## 依赖

- Git
- Python 3
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 或 [Codex CLI](https://github.com/openai/codex)（二选一）
- 可选：[Obsidian](https://obsidian.md)（图谱视图、反向链接、可视化浏览）

## 灵感来源

- [llm-wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) by Karpathy — 这个模式的起源

## License

MIT
