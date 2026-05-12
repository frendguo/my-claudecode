# Full Walkthrough — 一次完整 Multi-Agent Team 调度

本文档展示一次真实大型任务的完整调度顺序，使用 `TeamCreate` + Peer DM 模式。场景脱敏自一次实战：为某项目新增 IDE 扩展支持（约 23 工作日体量）。

## 目录

- [场景设定](#场景设定)
- [Step 1：调研 + 建事实清单](#step-1调研--建事实清单)
- [Step 2：TeamCreate + TaskCreate](#step-2teamcreate--taskcreate)
- [Step 3：同条消息并行起 4 个 teammate](#step-3同条消息并行起-4-个-teammate)
- [Step 4：Planner ↔ Gatekeeper Peer DM 循环](#step-4planner--gatekeeper-peer-dm-循环)
- [Step 5：Gatekeeper 通知 main agent → AskUserQuestion 范围决策](#step-5gatekeeper-通知-main-agent--askuserquestion-范围决策)
- [Step 6：Verifier + 可选并行 Phase 0](#step-6verifier--可选并行-phase-0)
- [Step 7：Verifier ↔ Gatekeeper Peer DM 审测试](#step-7verifier--gatekeeper-peer-dm-审测试)
- [Step 8：Executor 按 Phase 实施 + Peer DM 审](#step-8executor-按-phase-实施--peer-dm-审)
- [Step 9：收尾 shutdown_request + TeamDelete](#step-9收尾-shutdown_request--teamdelete)
- [Step 10：整体进度汇报 + 复盘](#step-10整体进度汇报--复盘)
- [失败回退处理](#失败回退处理)

## 场景设定

- **任务**：实施 GitLab issue #1 — 新增某 IDE 扩展，能力对齐现有同类实现
- **体量**：23 工作日，7 大交付项（A-G）
- **现有可对照实现**：项目内已有 `agent-support/intellij/` 和 `agent-support/vscode/`
- **用户请求**：通过多 agent 团队协作完成

## Step 1：调研 + 建事实清单

main agent 亲自做（不交给 sub-agent，因为后续审查都基于这份清单）：

```
1. 用 glab 或 gh 读 issue 全文
2. Glob/Grep 现有 intellij/vscode 实现路径
3. Read 关键文件，记 file:line 锚点
4. 整理事实清单（至少 10 条）
```

事实清单产出示例：

```markdown
## 已建立的事实锚点

- agent-support/intellij/.../bridge/BridgeClient.kt:42 — debounceMs = 300L
- agent-support/intellij/.../bridge/BridgeClient.kt:43 — beforeEditExpiryMs = 5000L
- agent-support/vscode/package.json:24-54 — 配置 key 有且仅有 3 个：
  - gitai.enableCheckpointLogging（bool, default false）
  - gitai.experiments.aiTabTracking（bool, default false）
  - gitai.blameMode（enum: off|line|all, default line）
- agent-support/vscode/package.json:67 — 快捷键 Ctrl+Shift+A 绑定 git-ai.toggleAICode
- 项目实际文档入口是 docs/README.md（不存在 docs/index.md）
- BridgeEvent 11 字段 canonical（event_id/type/session_id/agent_tool/project_name/project_path/terminal/machine_id/payload/timestamp/_ide_build）
- agent_tool 字段值采用枚举字符串，新扩展用 "{{NEW_TOOL_NAME}}"
- session_id 是纯 UUID（intellij/.../SessionLifecycle.kt:18）
- 已有 install.ps1 在仓库根，git blame 显示职责分工：...
- 测试框架使用 xUnit + Moq + FluentAssertions（参照 agent-support/vscode/test/）
```

这份清单后面会反复出现在 Gatekeeper 反馈的「已通过事实」段中。

## Step 2：TeamCreate + TaskCreate

```
TeamCreate({
  team_name: "issue-1-vs-extension",
  description: "实施 GitLab issue #1 — 新增 VS 扩展，对齐 intellij/vscode 能力（23d）"
})
```

这一步会创建：
- `~/.claude/teams/issue-1-vs-extension/config.json`
- `~/.claude/tasks/issue-1-vs-extension/`（共享 task list）

接下来 TaskCreate 建初始任务（之后 teammate 可以读 task list 协调）：

```
TaskCreate({ subject: "Plan: Planner 产出 v1", description: "基于 issue + 事实清单产出整体计划" })
TaskCreate({ subject: "Plan: Gatekeeper 审 v1", description: "对照事实清单逐条核查" })
TaskCreate({ subject: "Plan: 范围决策（AskUser）", description: "main agent 在 v1 通过后立刻执行" })
TaskCreate({ subject: "Test: Verifier 设计测试方案", description: "覆盖选定 Phase 的 GO 条件" })
TaskCreate({ subject: "Test: Gatekeeper 审测试方案" })
TaskCreate({ subject: "Code: Phase 0 脚手架" })
TaskCreate({ subject: "Code: Phase 0 审查" })
// ...按 Phase 继续
```

## Step 3：同条消息并行起 4 个 teammate

**关键**：4 个 `Agent` 调用放同一条消息内并行执行。Gatekeeper / Verifier / Executor 创建时只给「准备 idle 等通知」的 prompt；Planner 直接带 v1 任务启动。

```
[同一条 turn 中并行]

Agent({
  team_name: "issue-1-vs-extension",
  name: "gatekeeper",
  subagent_type: "general-purpose",
  description: "Gatekeeper 常驻审查",
  prompt: <copy templates/gatekeeper.md「初始化 Prompt」，填空 TEAM_NAME / MAIN_AGENT_NAME>
})

Agent({
  team_name: "issue-1-vs-extension",
  name: "planner",
  subagent_type: "Plan",
  description: "Planner v1 产出整体计划",
  prompt: <copy templates/planner.md「v1 初版 Prompt」，填空 TEAM_NAME / TASK_TITLE / ISSUE_OR_SPEC / ACK_FACTS / REFERENCE_IMPLS / KNOWN_CONSTRAINTS>
})

Agent({
  team_name: "issue-1-vs-extension",
  name: "verifier",
  subagent_type: "general-purpose",
  description: "Verifier 待 Planner 终版通过后接任务",
  prompt: "你是 team issue-1-vs-extension 的 Verifier。当前 idle 等待 main agent 派任务。team 协议见 templates/verifier.md。"
})

Agent({
  team_name: "issue-1-vs-extension",
  name: "executor",
  subagent_type: "general-purpose",
  description: "Executor 待测试方案通过后接任务",
  prompt: "你是 team issue-1-vs-extension 的 Executor。当前 idle 等待 main agent 派 Phase 任务。team 协议见 templates/executor.md。"
})
```

**为什么这一步并行启动**：4 个 teammate 立即都在 team 内可见。Planner 完成 v1 时直接 SendMessage 给 `gatekeeper`（已在 idle），不需要等 main agent 再起 Gatekeeper。

## Step 4：Planner ↔ Gatekeeper Peer DM 循环

main agent 启动 4 个 teammate 后**不需要做任何转发动作**。流程自动如下：

```
[Planner turn 1]
   产出 v1 → TaskUpdate(completed) → SendMessage({to: "gatekeeper", message: <v1 完整内容>})
   → idle

[系统自动唤醒 Gatekeeper（收到 planner 的 SendMessage）]
[Gatekeeper turn 1]
   读 v1 → Read/Grep 核查锚点 → 输出审查报告（按 templates/gatekeeper.md 反馈格式）
   → SendMessage({to: "planner", message: <审查报告，含「已通过事实」段 + P0/P1/P2>})
   → idle

[系统自动唤醒 Planner]
[Planner turn 2]
   读反馈 → 修订 v2（保留锁清单不动）→ SendMessage({to: "gatekeeper", message: <v2 完整>})
   → idle

[Gatekeeper turn 2]
   二审：核查 v1 反馈是否落地 + regression 检测 → SendMessage 反馈
   → idle

... (最多 3 轮)

[Gatekeeper turn 3 — 通过]
   SendMessage({to: "planner", summary: "v3 GO", message: "v3 通过，可以收工"})
   SendMessage({to: "<main agent name>", summary: "Planner v3 GO", message: "Planner v3 已通过审查，可以推进范围决策 + 派 Verifier"})
   → idle
```

**main agent 在这期间收到的消息**：
- 每个 turn 结束时 4 个 teammate 的 idle 通知（系统自动，不需要响应）
- peer DM 时收到 brief summary（系统自动在 idle 通知里附带摘要，main agent 知道 Planner / Gatekeeper 在对话但不需要介入）
- 最终收到 Gatekeeper 的 GO 通知 SendMessage

实战中此场景跑了 4 轮（v1→v4），第 2 轮出现严重 regression（已通过事实被 Planner 改错回去）——这是 SKILL.md 法则 1/2 的来源。Peer DM 模式下这种事故影响更大（没有 main agent 兜底），所以 Gatekeeper 反馈消息**必须**包含「已通过事实锁清单」。

## Step 5：Gatekeeper 通知 main agent → AskUserQuestion 范围决策

main agent 收到 Gatekeeper 的 GO 通知后**立刻**：

```
AskUserQuestion({
  questions: [
    {
      question: "本次会话推进到哪个 Phase？",
      header: "执行范围",
      multiSelect: false,
      options: [
        { label: "仅 Phase 0（脚手架 0.5d）",
          description: "本次只完成最小骨架，其他 Phase 下次会话继续" },
        { label: "Phase 0+1+2（基础设施 5d）",
          description: "完成脚手架 + 上报 + 核心 checkpoint" },
        { label: "Phase 0+1+2+3（含识别探针）",
          description: "需要实测环境（如 Copilot / 类似工具）" },
        { label: "全部 Phase 0-5c（4-5 周完整实现）",
          description: "单会话执行 23d 工作量风险极高，建议拆分" }
      ]
    },
    {
      question: "实测环境是否就绪？",
      header: "环境状态",
      multiSelect: false,
      options: [...]
    },
    {
      question: "执行阶段是否允许 Executor 自纠计划细节小问题？",
      header: "自纠权限",
      multiSelect: false,
      options: [
        { label: "允许直接修正（推荐）",
          description: "Executor 按真实 file:line 核对，发现不符直接采用实际值" },
        { label: "每个细节让 Gatekeeper 复审",
          description: "保证每字一句被验证，但显著拖慢节奏" }
      ]
    }
  ]
})
```

## Step 6：Verifier + 可选并行 Phase 0

main agent 拿到用户选定范围后派任务给 Verifier。如果 Phase 0 是无业务依赖的脚手架，**同一条消息**内也给 Executor 派 Phase 0：

```
[同一条 turn 中并行 SendMessage]

SendMessage({
  to: "verifier",
  summary: "派任务: 设计测试矩阵",
  message: <copy templates/verifier.md「Verifier Prompt」，填空 TEAM_NAME / APPROVED_PLAN / SCOPE_PHASES=Phase 0+1+2 / TEST_FRAMEWORK / REFERENCE_TESTS>
})

SendMessage({
  to: "executor",
  summary: "派任务: Phase 0 脚手架",
  message: <copy templates/executor.md「Executor Prompt」，填空 PHASE_NUM=0 / APPROVED_PLAN=Phase 0 章节 / APPROVED_TESTS="测试方案设计中" / ALLOW_PLAN_FIXUP=true>
})
```

如果 Phase 0 涉及业务决策或依赖 Verifier 输出，则**串行**（先派 Verifier，等通过后再派 Executor）。

## Step 7：Verifier ↔ Gatekeeper Peer DM 审测试

类似 Step 4 的 peer DM 循环：

```
[Verifier 完成测试矩阵]
   → SendMessage({to: "gatekeeper", message: <测试方案完整>})

[Gatekeeper 按模式 B 审查]
   → 通过 → SendMessage({to: "verifier", "GO"}) + SendMessage({to: <main agent>, "Verifier GO"})
   → 不通过 → SendMessage({to: "verifier", <反馈>}) → 循环

[Verifier 修订到通过]
```

实战中测试方案审查通常 1-2 轮就通过——测试设计比计划更结构化，争议少。

## Step 8：Executor 按 Phase 实施 + Peer DM 审

每个 Phase 流程：

```
[Executor turn]
   实施代码 + 跑测试 + git commit → TaskUpdate(completed)
   → SendMessage({to: "gatekeeper", summary: "Phase N 送审", message: "<实施报告 + commit hash>"})
   → idle

[Gatekeeper 按模式 C 审查]
   → 跑 git diff + 测试命令 + 锚点核查
   → 不通过：SendMessage({to: "executor", <反馈，含锁清单>})
   → 通过：
     SendMessage({to: "executor", "GO"})
     SendMessage({to: <main agent>, "Phase N GO"})

[main agent 收到 Phase N GO 通知]
   → 派 Phase N+1：
     SendMessage({to: "executor", message: <templates/executor.md「滚动派下一 Phase」模板>})
   → 循环
```

Executor 必须 commit 后才能通知 Gatekeeper（法则 4）。修订时不要 amend 已审过的 commit。

## Step 9：收尾 shutdown_request + TeamDelete

全部选定 Phase 完成且通过审查后，main agent：

```
[同一条 turn 中给每个 teammate 发 shutdown_request]

SendMessage({
  to: "planner",
  message: { type: "shutdown_request", reason: "全部任务完成" }
})
SendMessage({
  to: "verifier",
  message: { type: "shutdown_request", reason: "全部任务完成" }
})
SendMessage({
  to: "executor",
  message: { type: "shutdown_request", reason: "全部任务完成" }
})
SendMessage({
  to: "gatekeeper",
  message: { type: "shutdown_request", reason: "全部任务完成" }
})
```

每个 teammate 收到后回 `{type: "shutdown_response", request_id, approve: true}` 并自动终止进程。

全部 teammate 关停后：

```
TeamDelete()
```

清理 team 目录 + task 目录。

## Step 10：整体进度汇报 + 复盘

会话结束前汇报：

```markdown
## 整体进度汇报

经过完整的 multi-agent team 协作（peer DM 模式），Phase 0+1+2 已实施完成并通过 Gatekeeper 审查。

### 多 agent 协作轨迹

| 阶段 | 角色 | 轮次 | Peer DM 链 |
|------|-------|------|---|
| 计划 | planner ↔ gatekeeper | v1→v4 | Planner→GK 4 次，GK→Planner 4 次 |
| 测试 | verifier ↔ gatekeeper | v1→v2 | Verifier→GK 2 次，GK→Verifier 2 次 |
| Phase 0 | executor ↔ gatekeeper | v1 | 1 轮通过 |
| Phase 1 | executor ↔ gatekeeper | v1→v2 | 1 处 P0 |
| Phase 2 | executor ↔ gatekeeper | v1 | 1 轮通过 |

### 已交付

{文件清单 + 测试通过数 + commit 链}

### 余下 Phase（未实施）

{表格 + 估时}

### 你下一步可选

1. 本地验证：...
2. 提交当前进度：...
3. 继续 Phase N（新会话）：在新会话 `git log --grep="Phase"` 续接，或新建 Team
```

复盘点（更新 SKILL.md / templates/*.md）：

- Gatekeeper 返工率最高的轮次 → 反馈模板「已通过事实锁清单」段是否需要补强？
- Peer DM 是否成功（vs Gatekeeper 误发给 main agent 拖慢节奏）？
- 范围决策是否在合适时机？
- 是否有可并行被串行的步骤？
- TaskUpdate owner 字段是否被正确使用？

## 失败回退处理

### 情形 1：Gatekeeper 3 轮仍 NO-GO 同一问题

Gatekeeper 在第 3 轮 NO-GO 时主动 SendMessage 给 main agent：

```
SendMessage({
  to: <main agent>,
  summary: "卡点：P0-X 3 轮 NO-GO",
  message: "P0-X 已 3 轮 NO-GO，争论点：{summary}。\n\n两方意见：\n- Planner 立场：...\n- 我的立场：...\n\n请用户裁决方向，我据此放行或继续修订。"
})
```

main agent 收到后向用户 AskUserQuestion 裁决，再 SendMessage 通知双方决议。

### 情形 2：会话 token 预算告急

```
1. 立即 SendMessage 给 Executor："不论当前进度，跑完测试 + commit 当前所有变更，然后 idle"
2. 等待 commit 完成通知
3. SendMessage shutdown_request 给所有 teammate
4. TeamDelete()
5. 向用户报告：
   "当前进度：Phase {N} 已 commit (commit-hash)。
   剩余 Phase {N+1..} 估时 {D}d，建议新会话续接。
   续接锚点：{...}
   续接方式：新会话起一个新 team（或复用 ~/.claude/teams/{name}/，但 teammate 进程已关停需重新 Agent）"
```

### 情形 3：Planner 反复引入 regression

如果 v2/v3 都有 regression，原因通常是：

- Gatekeeper 反馈没列出「已通过事实」锁清单 → 改 templates/gatekeeper.md 反馈段
- Gatekeeper 反馈锁清单不完整 → 加固审查模式 A 的 Step 4 (Regression 检测)
- Planner 修订纪律部分被忽略 → 加固 templates/planner.md「修订指引」

### 情形 4：实际任务体量远小于估计

如发现整个任务实际不到 1 工作日：

```
1. SendMessage shutdown_request 给所有 teammate
2. TeamDelete()
3. main agent 直接做
4. 向用户报告：
   "经评估，本任务实际体量约 {N} 小时，multi-agent 协作开销不划算（TeamCreate / 4 teammate / 反复 peer DM）。
   我将直接实施。"
```

### 情形 5：teammate 误把消息发给 main agent 而不是同伴

实战中可能发生：Gatekeeper 反馈本应发给 Planner，却误发给 main agent 让转发。处理：

- main agent 收到后**不要直接转发**——这会让 Gatekeeper 误以为 main 仍在循环里
- 立即 SendMessage 给该 Gatekeeper：「请直接发给 planner，peer DM 协议见 templates/gatekeeper.md」
- 同时把原反馈 SendMessage 给 planner，标注「Gatekeeper 误发，我转给你」

这种情况若反复发生，说明 prompt 里 Team 协作协议段不够醒目，需要加固 templates。
