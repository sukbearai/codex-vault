# Codex-Vault

> 给任何 LLM agent 加上持久记忆。
> 你的笔记，你的 git，你的数据。

## 问题

LLM agent 每次对话都从零开始。上次做的决策忘了，讨论过的方案忘了，知识永远无法积累。

## 方案

一个结构化的知识库 + 3 个 hook，让 agent 拥有跨 session 的记忆。支持 **Claude Code** 和 **Codex CLI**。纯 markdown + git，没有外部依赖。

## 核心用法

6 个动作，覆盖日常全部场景：

| 动作 | 怎么做 | 什么时候用 |
|------|--------|-----------|
| **设目标** | 编辑 `brain/North Star.md` | 首次使用，或方向调整时 |
| **随手记** | `/dump 内容` | 做了决策、有了想法、完成了什么 — 随时 dump |
| **查记忆** | `/recall 关键词` | 忘了之前的决策、想找历史笔记 |
| **吃内容** | `/ingest URL或文件` | 看到好文章、拿到新资料，结构化存入 |
| **收尾** | `/wrap-up` | session 结束前，检查质量、更新索引 |
| **体检** | `/lint` | vault 健康审计 — 断链、孤儿、过期、标签漂移等 13 项检查 |

> Codex CLI 用 `$dump`、`$recall`、`$ingest`、`$wrap-up`、`$lint`。

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

**`/lint` — 体检**
```
/lint
```
> 不需要参数，自动执行 13 项 vault 健康检查。

日常最高频的就是 `/dump`。其他按需使用。

## 30 秒上手

```bash
# 在你的项目目录下：
npx @suwujs/codex-vault init
claude                                  # 或: codex
```

填好 `.vault/brain/North Star.md`，开始对话。

> **集成模式**（在其他项目中运行 `init` 时的默认行为）会创建 `.vault/` — 一个隐藏目录，自动加入 `.gitignore`，每个开发者各自拥有本地 vault，不会产生合并冲突。**独立模式**（在 codex-vault 仓库内）仍然使用 `vault/`。

<details>
<summary>其他安装方式：从源码安装</summary>

```bash
git clone https://github.com/sukbearai/codex-vault.git /tmp/codex-vault
bash /tmp/codex-vault/plugin/install.sh
```

> **独立模式**：在 codex-vault 仓库内运行 `install.sh`，以 `vault/`（而非 `.vault/`）为工作目录。
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

Hook 驱动整个循环：

| Hook | 触发时机 | 做什么 | Claude Code | Codex CLI |
|------|---------|--------|-------------|-----------|
| **session-start** | Agent 启动 | 注入 North Star 目标、近期 git 变更、活跃项目、vault 文件清单 | SessionStart | SessionStart |
| **classify-message** | 每条消息 | 检测决策、成果、项目更新 — 提示 agent 该归档到哪里 | UserPromptSubmit | UserPromptSubmit |
| **validate-write** | 写 `.md` 后 / 执行 Bash 后 | 检查 frontmatter 和 wikilinks（Claude）；检测命令失败（Codex） | PostToolUse (Write\|Edit) | PostToolUse (Bash) |

## 支持的 Agent

| Agent | Hooks | Skills | 状态 |
|-------|-------|--------|------|
| Claude Code | `.claude/settings.json` 3 hooks | `/dump` `/recall` `/ingest` `/wrap-up` `/lint` | 完整支持 |
| Codex CLI | `.codex/hooks.json` 3 hooks | `$dump` `$recall` `$ingest` `$wrap-up` `$lint` | 完整支持 |
| 其他 | 写适配器（[指南](docs/adding-an-agent.md)） | 取决于 agent | 社区贡献 |

## Vault 结构

集成模式下 vault 位于 `.vault/`（隐藏目录，默认已 gitignore）。独立模式下位于 `vault/`。内部结构相同：

```
.vault/                   （集成模式）或 vault/（独立模式）
  Home.md                 入口 — 当前焦点、快速链接
  SCHEMA.md               域定义、标签分类法、页面阈值
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

八个目录，一份 Schema，五种笔记类型。

## 使用场景

详见 [docs/usage.md](docs/usage.md) — 7 个真实场景，从首次安装到项目完成，每一步都有输入和输出示例。

## v0.8.0 新特性

- **`/lint` skill** — 13 项 vault 健康审计：断链、孤儿页面、索引完整性、frontmatter 校验、过期内容、大页面、标签审计、日志检查、索引膨胀、日志轮转、拆分建议、归档完整性、主题地图
- **`SCHEMA.md`** — 域定义、标签分类法（先声明后使用）、页面阈值（创建/更新/拆分/归档）、frontmatter 规范
- **矛盾追踪** — `contradictions` frontmatter 字段，双向标记冲突信息；`/ingest` 自动检测与现有内容的矛盾
- **批量摄入** — `/ingest` 支持多源批量处理，跨源去重、单次搜索、统一索引更新
- **回写决策逻辑** — `/recall` 使用 4 条保存 / 3 条不保存的决策矩阵；`synthesized_from` 字段追踪来源页面
- **Obsidian 集成指南** — [docs/obsidian.md](docs/obsidian.md)，含 Dataview 查询、Graph View 技巧、推荐配置
- **预读协议** — 5 个 skill 均以 Step 0 上下文检查开始（读取 `work/Index.md` + `SCHEMA.md`）
- **新 frontmatter 字段** — `type`（work/decision/source-summary/reference/thinking）、`sources`（源文档路径）、`synthesized_from`（综合引用来源）
- **Hook 增强** — session-start 注入 SCHEMA 上下文（标签分类法 + 页面阈值）；validate-write 校验标签白名单和 type 字段
- **`/wrap-up` 增强** — 归档时自动迁移反向链接，3+ 笔记 session 后推荐运行 lint
- **11 条 Pitfalls 防错清单** — 常见反模式（详见 `plugin/instructions.md` 和 `vault/CLAUDE.md`）
- **5 个模板重构** — 所有模板增加内容结构规范和新 frontmatter 字段

## 设计原则

1. **数据主权** — 你的 markdown，你的 git，你的机器。没有云端锁定。
2. **Agent 无关** — hook 是通用接口。一个 vault，多个 agent。
3. **默认极简** — 3 个 hook，~100 行指令。按需增加复杂度。
4. **图优先** — 目录按用途分组，`[[wikilinks]]` 按语义分组。链接是主要的组织工具。
5. **面向未来** — 即使模型有了内建记忆，vault 仍然有价值：可审计、可迁移、git 追踪的本地存储。

## CLI

```bash
npx @suwujs/codex-vault init        # 安装 .vault/ + hooks 到当前项目
npx @suwujs/codex-vault upgrade     # 升级 hooks 和 skills（保留 vault 数据）
npx @suwujs/codex-vault uninstall   # 移除 hooks 和 skills（保留 vault 数据）
npx @suwujs/codex-vault doctor      # 诊断 agent 配置导致的 git 冲突
npx @suwujs/codex-vault doctor --fix  # 自动修复：gitignore、取消追踪、迁移 vault/→.vault/
# init 会自动将 .vault/、.claude/、.codex/ 加入 .gitignore — 每位开发者拥有独立的本地 vault。
```

### 修复团队协作中的 Git 冲突

如果 `.claude/`、`.codex/` 或 `vault/` 文件已经被提交并引起合并冲突：

```bash
# 诊断（不做任何修改）
npx @suwujs/codex-vault doctor

# 自动修复并提交
npx @suwujs/codex-vault doctor --fix
```

`doctor --fix` 做什么：

| 检查项 | 问题 | 修复方式 |
|--------|------|---------|
| gitignore | `.vault/` `.claude/` `.codex/` 不在 `.gitignore` 中 | 追加条目 |
| 已追踪文件 | agent 文件已提交到 git | `git rm --cached`（从索引移除，本地文件保留） |
| vault 迁移 | 旧版 `vault/` 应为 `.vault/` | 重命名 + 清理残留配置 |
| codex-mem 重命名 | 旧版 `.codex-mem/` 目录 | 重命名为 `.codex-vault/` |
| 残留配置 | `.vault/` 内部有 `.claude/` `.codex/` | 删除（应在项目根目录） |
| 冲突标记 | 配置文件中有 `<<<<<<<` | 报告，需手动解决 |
| JSON 损坏 | settings/hooks 解析错误 | 报告，建议重新 `init` |

不需要先 upgrade — `npx` 会自动使用最新版本。

修复后，团队每位成员各自运行 `npx @suwujs/codex-vault init` 重新生成本地 agent 配置即可。

## 测试

```bash
npm test                # 完整 E2E 测试
npm run test:cli        # CLI 命令测试（22 个）
npm run test:hooks      # Hook 脚本测试（33 个）
```

## 配置

| 配置项 | 文件 | 说明 |
|--------|------|------|
| 自动执行 skills | `.vault/.codex-vault/config.json`（独立模式为 `vault/.codex-vault/config.json`） | `{"classify_mode": "auto"}` — 检测到意图后自动执行对应 skill，而非建议 |

## 依赖

- Git
- Python 3
- Node.js >= 18（CLI 安装用）
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 或 [Codex CLI](https://github.com/openai/codex)（二选一）
- 可选：[Obsidian](https://obsidian.md)（图谱视图、反向链接、可视化浏览）

## 灵感来源

- [llm-wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) by Karpathy — 这个模式的起源

## License

MIT
