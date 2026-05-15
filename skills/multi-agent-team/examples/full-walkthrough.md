# Full Walkthrough — 一次完整 Multi-Agent Team 调度

本文档展示一次真实大型任务的完整调度顺序，使用 `TeamCreate` + Peer DM + 三 Gatekeeper + artifact 持久化模式。场景脱敏自一次实战：为某项目新增 IDE 扩展支持（约 23 工作日体量）。

## 目录

- [场景设定](#场景设定)
- [Step 1：mkdir + 调研 + 写 facts.md](#step-1mkdir--调研--写-factsmd)
- [Step 2：TeamCreate + TaskCreate](#step-2teamcreate--taskcreate)
- [Step 3：同条消息并行起 6 个 teammate](#step-3同条消息并行起-6-个-teammate)
- [Step 4：Planner ↔ gatekeeper-plan Peer DM 循环](#step-4planner--gatekeeper-plan-peer-dm-循环)
- [Step 5：gatekeeper-plan 通知 main agent → AskUserQuestion 范围决策](#step-5gatekeeper-plan-通知-main-agent--askuserquestion-范围决策)
- [Step 6：Verifier + 可选并行 Phase 0](#step-6verifier--可选并行-phase-0)
- [Step 7：Verifier ↔ gatekeeper-test Peer DM 审测试](#step-7verifier--gatekeeper-test-peer-dm-审测试)
- [Step 8：Executor 按 Phase 实施 + Peer DM 审](#step-8executor-按-phase-实施--peer-dm-审)
- [Step 9：收尾 shutdown_request + TeamDelete](#step-9收尾-shutdown_request--teamdelete)
- [Step 10：整体进度汇报 + 复盘](#step-10整体进度汇报--复盘)
- [会话续接示例](#会话续接示例)
- [失败回退处理](#失败回退处理)

## 场景设定

- **任务**：实施 GitLab issue #1 — 新增某 IDE 扩展，能力对齐现有同类实现
- **体量**：23 工作日，7 大交付项（A-G）
- **现有可对照实现**：项目内已有 `agent-support/intellij/` 和 `agent-support/vscode/`
- **用户请求**：通过多 agent 团队协作完成

## Step 1：mkdir + 调研 + 写 facts.md

main agent 亲自做（不交给 teammate，因为后续审查都基于这份清单）：

```
1. 创建目录 .multi-agent/issue-1-vs-extension/ 及子目录 plan/ test/ code/ locks/ decisions/
2. 用 glab 或 gh 读 issue 全文
3. Glob/Grep 现有 intellij/vscode 实现路径
4. Read 关键文件，记 file:line 锚点
5. Write 事实清单到 .multi-agent/issue-1-vs-extension/facts.md（至少 10 条）
```

facts.md 产出示例：

```markdown
# 已建立的事实锚点

- agent-support/intellij/.../bridge/BridgeClient.kt:42 — debounceMs = 300L
- agent-support/intellij/.../bridge/BridgeClient.kt:43 — beforeEditExpiryMs = 5000L
- agent-support/vscode/package.json:24-54 — 配置 key 有且仅有 3 个：
  - gitai.enableCheckpointLogging（bool, default false）
  - gitai.experiments.aiTabTracking（bool, default false）
  - gitai.blameMode（enum: off|line|all, default line）
- agent-support/vscode/package.json:67 — 快捷键 Ctrl+Shift+A 绑定 git-ai.toggleAICode
- 项目实际文档入口是 docs/README.md（不存在 docs/index.md）
- BridgeEvent 11 字段 canonical（event_id/type/session_id/agent_tool/project_name/project_path/terminal/machine_id/payload/timestamp/_ide_build）
- agent_tool 字段值采用枚举字符串，新扩展用 "visualstudio"
- session_id 是纯 UUID（intellij/.../SessionLifecycle.kt:18）
- 已有 install.ps1 在仓库根，git blame 显示职责分工：...
- 测试框架使用 xUnit + Moq + FluentAssertions（参照 agent-support/vscode/test/）
```

这份清单后面会被三个 Gatekeeper 通过 Read 引用——它们的反馈中「已通过事实锁清单」会增量追加到 `locks/approved-facts.md`。

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
TaskCreate({ subject: "Plan: Planner 产出 v1", description: "基于 issue + facts.md 产出整体计划写到 plan/v1.md" })
TaskCreate({ subject: "Plan: gatekeeper-plan 审 v1", description: "对照 facts.md 逐条核查" })
TaskCreate({ subject: "Plan: 范围决策（AskUser）", description: "main agent 在 v1 通过后立刻执行，写到 decisions/scope.md" })
TaskCreate({ subject: "Test: Verifier 设计测试方案", description: "覆盖选定 Phase 的 GO 条件，写到 test/v1.md" })
TaskCreate({ subject: "Test: gatekeeper-test 审测试方案" })
TaskCreate({ subject: "Code: Phase 0 脚手架" })
TaskCreate({ subject: "Code: Phase 0 审查" })
// ...按 Phase 继续
```

## Step 3：同条消息并行起 6 个 teammate

**关键**：6 个 `Agent` 调用放同一条消息内并行执行。三个 Gatekeeper / Verifier / Executor 创建时只给「准备 idle 等通知」的 prompt；Planner 直接带 v1 任务启动。

```
[同一条 turn 中并行]

Agent({
  team_name: "issue-1-vs-extension",
  name: "gatekeeper-plan",
  subagent_type: "general-purpose",
  description: "gatekeeper-plan 审 Planner 产出",
  prompt: <copy templates/gatekeeper-plan.md「初始化 Prompt」>
})

Agent({
  team_name: "issue-1-vs-extension",
  name: "gatekeeper-test",
  subagent_type: "general-purpose",
  description: "gatekeeper-test 审 Verifier 产出",
  prompt: <copy templates/gatekeeper-test.md「初始化 Prompt」>
})

Agent({
  team_name: "issue-1-vs-extension",
  name: "gatekeeper-code",
  subagent_type: "general-purpose",
  description: "gatekeeper-code 跨 Phase 审 Executor",
  prompt: <copy templates/gatekeeper-code.md「初始化 Prompt」>
})

Agent({
  team_name: "issue-1-vs-extension",
  name: "planner",
  subagent_type: "Plan",
  description: "Planner v1 产出整体计划",
  prompt: <copy templates/planner.md「v1 初版 Prompt」>
})

Agent({
  team_name: "issue-1-vs-extension",
  name: "verifier",
  subagent_type: "general-purpose",
  description: "Verifier 待计划通过后接任务",
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

**为什么这一步并行启动**：6 个 teammate 立即都在 team 内可见。Planner 完成 v1 时直接 SendMessage 给 `gatekeeper-plan`（已在 idle），不需要等 main agent 再起 Gatekeeper。

**为什么 idle 不浪费 token**：每个 teammate idle 时只接收系统通知，不主动产出。被 wakeup 时才计费 turn。

## Step 4：Planner ↔ gatekeeper-plan Peer DM 循环

main agent 启动 6 个 teammate 后**不需要做任何转发动作**。流程自动如下：

```
[Planner turn 1]
   first action: Read .multi-agent/issue-1-vs-extension/facts.md
   产出 plan/v1.md → TaskUpdate(completed)
   → SendMessage({to: "gatekeeper-plan", summary: "v1 计划送审", message: "v1 计划完成，请审查。\nartifact: .multi-agent/issue-1-vs-extension/plan/v1.md\n摘要：6 个 Phase, 23d 估时, ..."})
   → idle

[系统自动唤醒 gatekeeper-plan（收到 planner 的 SendMessage）]
[gatekeeper-plan turn 1]
   first action: Read locks/approved-facts.md (不存在跳过) + Read facts.md + Read plan/v1.md
   核查锚点 → 写 plan/v1-review.md（按 templates/gatekeeper.md 反馈格式，第一段「已通过事实」本轮新增 0 条）
   → SendMessage({to: "planner", summary: "v1 审查：要求修改", message: "v1 审查完成：要求修改。\nreview: .multi-agent/issue-1-vs-extension/plan/v1-review.md\n本轮：P0 3 项, P1 5 项, P2 2 项"})
   → idle

[系统自动唤醒 Planner]
[Planner turn 2]
   Read plan/v1-review.md + Read locks/approved-facts.md
   修订 → 写 plan/v2.md（保留锁清单不动）
   → SendMessage({to: "gatekeeper-plan", summary: "v2 计划送审", message: "..."})
   → idle

[gatekeeper-plan turn 2]
   Read plan/v2.md + plan/v1-review.md（确认上轮反馈）
   二审：核查 v1 反馈是否落地 + regression 检测 → 写 plan/v2-review.md
   → SendMessage 反馈
   → idle

... (最多 3 轮)

[gatekeeper-plan turn 3 — 通过]
   copy plan/v3.md → plan/FINAL.md
   追加新通过事实到 locks/approved-facts.md（每条带 [plan] 标签）
   两个 SendMessage：
   - to: planner, "v3 通过审查。可以收工。"
   - to: <main agent name>, "Planner v3 GO，可以推进范围决策 + 派 Verifier"
   → idle
```

**main agent 在这期间收到的消息**：
- 每个 turn 结束时 6 个 teammate 的 idle 通知（系统自动，不需要响应）
- peer DM 时收到 brief summary（系统自动在 idle 通知里附带摘要）
- 最终收到 gatekeeper-plan 的 GO 通知 SendMessage

**消息体节省效果**：v1 全文塞 SendMessage 约 4-5k token，改路径引用后只剩 200-300 token；3 轮 plan 反复传递省下 10-15k token。

实战中此场景跑了 4 轮（v1→v4），第 2 轮出现严重 regression（已通过事实被 Planner 改错回去）——这是 SKILL.md 法则 1/2 的来源。Peer DM 模式下这种事故影响更大（没有 main agent 兜底），所以 Gatekeeper 反馈消息**必须**追加到 `locks/approved-facts.md`，且 Planner 修订时必须 Read 该文件。

## Step 5：gatekeeper-plan 通知 main agent → AskUserQuestion 范围决策

main agent 收到 gatekeeper-plan 的 GO 通知后**立刻**：

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
        { label: "每个细节让 gatekeeper-code 复审",
          description: "保证每字一句被验证，但显著拖慢节奏" }
      ]
    }
  ]
})
```

拿到答案后**立刻** Write 决策结果到 `.multi-agent/issue-1-vs-extension/decisions/scope.md`：

```markdown
# 范围决策

- 推进范围：Phase 0+1+2
- 实测环境：就绪
- 自纠权限：允许

决策时间：<填写决策日期>
```

## Step 6：Verifier + 可选并行 Phase 0

main agent 拿到用户选定范围后派任务给 Verifier。如果 Phase 0 是无业务依赖的脚手架，**同一条消息**内也给 Executor 派 Phase 0：

```
[同一条 turn 中并行 SendMessage]

SendMessage({
  to: "verifier",
  summary: "派任务: 设计测试矩阵",
  message: <copy templates/verifier.md「Verifier Prompt」，填空 TEAM_NAME / TEAM_DIR / TEST_FRAMEWORK / REFERENCE_TESTS>
})

SendMessage({
  to: "executor",
  summary: "派任务: Phase 0 脚手架",
  message: <copy templates/executor.md「Executor Prompt」，填空 PHASE_NUM=0 / TEAM_DIR / ALLOW_PLAN_FIXUP=true>
})
```

如果 Phase 0 涉及业务决策或依赖 Verifier 输出，则**串行**（先派 Verifier，等通过后再派 Executor）。

## Step 7：Verifier ↔ gatekeeper-test Peer DM 审测试

类似 Step 4 的 peer DM 循环：

```
[Verifier first action]
   Read plan/FINAL.md + decisions/scope.md + locks/approved-facts.md

[Verifier 完成测试矩阵]
   写 test/v1.md
   → SendMessage({to: "gatekeeper-test", summary: "测试方案 v1 送审", message: "...artifact: ...test/v1.md..."})

[gatekeeper-test first action]
   Read locks/approved-facts.md（已含 plan 阶段事实）+ plan/FINAL.md + decisions/scope.md + test/v1.md
   按模式 B 审查 → 写 test/v1-review.md
   → 通过：copy → test/FINAL.md + 追加 locks/approved-facts.md（[test] 标签）+
     SendMessage({to: "verifier", "GO"}) + SendMessage({to: <main agent>, "Verifier GO"})
   → 不通过：SendMessage({to: "verifier", <反馈摘要+路径>}) → 循环

[Verifier 修订到通过]
```

实战中测试方案审查通常 1-2 轮就通过——测试设计比计划更结构化，争议少。

## Step 8：Executor 按 Phase 实施 + Peer DM 审

每个 Phase 流程：

```
[Executor turn]
   first action（首次）: Read plan/FINAL.md + test/FINAL.md + locks/approved-facts.md + REFERENCE_IMPLS
   实施代码 + 跑测试 + git commit
   写实施报告到 code/phase-N/v1.md（含 commit hash）
   → TaskUpdate(completed)
   → SendMessage({to: "gatekeeper-code", summary: "Phase N v1 送审", message: "...artifact: ...code/phase-N/v1.md\ncommit: <hash>..."})
   → idle

[gatekeeper-code first action（首个 Phase 时）]
   Read locks/approved-facts.md + plan/FINAL.md + test/FINAL.md + code/phase-N/v1.md
   按模式 C 审查（git diff <prev>..HEAD + 跑测试 + 锚点核查）
   → 写 code/phase-N/review-v1.md
   → 不通过：SendMessage({to: "executor", <反馈摘要+路径>})
   → 通过：
     copy code/phase-N/v1.md → code/phase-N/FINAL.md
     追加 locks/approved-facts.md（[code-phase-N] 标签）
     SendMessage({to: "executor", "GO"})
     SendMessage({to: <main agent>, "Phase N GO"})

[main agent 收到 Phase N GO 通知]
   → 派 Phase N+1：
     SendMessage({to: "executor", message: <templates/executor.md「滚动派下一 Phase」模板>})
   → 循环
```

Executor 必须 commit + 写 v{R}.md 后才能通知 gatekeeper-code（法则 4）。修订时不要 amend 已审过的 commit，新报告写到 v2.md / v3.md。

## Step 9：收尾 shutdown_request + TeamDelete

全部选定 Phase 完成且通过审查后，main agent：

```
[同一条 turn 中给每个 teammate 发 shutdown_request]

SendMessage({to: "planner", message: { type: "shutdown_request", reason: "全部任务完成" }})
SendMessage({to: "verifier", message: { type: "shutdown_request", reason: "全部任务完成" }})
SendMessage({to: "executor", message: { type: "shutdown_request", reason: "全部任务完成" }})
SendMessage({to: "gatekeeper-plan", message: { type: "shutdown_request", reason: "全部任务完成" }})
SendMessage({to: "gatekeeper-test", message: { type: "shutdown_request", reason: "全部任务完成" }})
SendMessage({to: "gatekeeper-code", message: { type: "shutdown_request", reason: "全部任务完成" }})
```

每个 teammate 收到后回 `{type: "shutdown_response", request_id, approve: true}` 并自动终止进程。

全部 teammate 关停后：

```
TeamDelete()
```

清理 `~/.claude/teams/<name>/` + `~/.claude/tasks/<name>/`。

**`.multi-agent/issue-1-vs-extension/` 保留**——main agent 向用户提示：

```
.multi-agent/issue-1-vs-extension/ 保留在项目根。包含完整决策上下文（plan/test/code 各阶段 v1..vN + FINAL + 审查报告 + 锁清单）。

你可以选择：
- 加入 .gitignore（如视为临时工作区）
- git add 跟踪（如想审计决策过程）
- 手动删除（如确定不再需要）
```

## Step 10：整体进度汇报 + 复盘

会话结束前汇报：

```markdown
## 整体进度汇报

经过完整的 multi-agent team 协作（peer DM + 三 Gatekeeper + artifact 持久化），Phase 0+1+2 已实施完成并通过审查。

### 多 agent 协作轨迹

| 阶段 | 角色 | 轮次 | artifact |
|------|-------|------|---|
| 计划 | planner ↔ gatekeeper-plan | v1→v4 | plan/v1..v4.md + FINAL.md + reviews |
| 测试 | verifier ↔ gatekeeper-test | v1→v2 | test/v1..v2.md + FINAL.md |
| Phase 0 | executor ↔ gatekeeper-code | v1 | code/phase-0/v1.md + FINAL.md |
| Phase 1 | executor ↔ gatekeeper-code | v1→v2 | code/phase-1/v1..v2.md + FINAL.md |
| Phase 2 | executor ↔ gatekeeper-code | v1 | code/phase-2/v1.md + FINAL.md |

### 已交付

{文件清单 + 测试通过数 + commit 链}

### 余下 Phase（未实施）

{表格 + 估时}

### .multi-agent/ 处置

`.multi-agent/issue-1-vs-extension/` 保留。建议：{加入 .gitignore / git add / 手动删除}

### 你下一步可选

1. 本地验证：...
2. 提交当前进度：...
3. 继续 Phase N（新会话）：在新会话主动说"续接 issue-1-vs-extension"，main agent 会从 .multi-agent/ + git log 重建上下文
```

复盘点清单见 SKILL.md「持续改进」节——逐项检查后把新发现更新回 SKILL.md / templates/*.md。

## 会话续接示例

用户在新会话主动说："续上次的 issue-1-vs-extension 多 agent 任务"。

main agent 处理：

```
1. ls .multi-agent/issue-1-vs-extension/  → 确认目录存在
2. Read facts.md, decisions/scope.md, locks/approved-facts.md
3. Read plan/FINAL.md, test/FINAL.md（如已存在）
4. ls code/  → 看到 phase-0/, phase-1/, phase-2/
5. 检查每个 phase-N/ 是否有 FINAL.md → 确定哪些已通过
6. git log --grep="Phase" → 验证 commit 状态
7. 综合判断当前进度，AskUserQuestion 确认续接点：

AskUserQuestion({
  questions: [{
    question: "上次进度：Phase 0/1/2 已通过（commit链：a1b2c3 → d4e5f6 → g7h8i9）。从 Phase 3 续接？",
    header: "续接点",
    multiSelect: false,
    options: [
      { label: "从 Phase 3 续接（推荐）",
        description: "继续推进剩余 Phase 3-5c" },
      { label: "重审 Phase 2",
        description: "如对 Phase 2 实施有疑虑，重新走一遍 gatekeeper-code 审查" },
      { label: "重新做范围决策",
        description: "重新评估剩余 Phase 优先级" }
    ]
  }]
})

8. 用户选 1 后：
   - TeamCreate({team_name: "issue-1-vs-extension"})（同名复用；若已 TeamDelete 会重建 ~/.claude/teams/ 目录）
   - 同条消息起 6 个 teammate（gatekeeper-{plan,test,code} 起步会自行 Read locks/ 重建基线）
     注：plan 阶段已完结，gatekeeper-plan 仅作 idle 占位，不会再被唤醒
   - SendMessage(executor, 派 Phase 3，引用 plan/FINAL.md + test/FINAL.md)
   - 流程进入 Step 8 循环
```

## 失败回退处理

### 情形 1：Gatekeeper 3 轮仍 NO-GO 同一问题

对应 Gatekeeper 在第 3 轮 NO-GO 时主动 SendMessage 给 main agent：

```
SendMessage({
  to: <main agent>,
  summary: "卡点：P0-X 3 轮 NO-GO",
  message: "P0-X 已 3 轮 NO-GO，争论点：{summary}。\nreviews: review-v1.md, review-v2.md, review-v3.md\n\n两方意见：\n- 被审者立场：...\n- 我的立场：...\n\n请用户裁决方向，我据此放行或继续修订。"
})
```

main agent 收到后向用户 AskUserQuestion 裁决，再 SendMessage 通知双方决议。

### 情形 2：会话 token 预算告急

```
1. 立即 SendMessage 给 Executor："不论当前进度，跑完测试 + commit 当前所有变更 + 写 code/phase-N/v{R}.md，然后 idle"
2. 等待 commit + artifact 完成通知
3. SendMessage shutdown_request 给所有 teammate（6 个）
4. TeamDelete()
5. 向用户报告：
   "当前进度：Phase {N} 已 commit (commit-hash) + 写 .multi-agent/.../code/phase-N/v{R}.md
   剩余 Phase {N+1..} 估时 {D}d，建议新会话主动说『续接 <team-name>』续接
   续接靠 .multi-agent/<team>/ + git log 自动重建（详见 SKILL.md 「会话续接」节）
   .multi-agent/<team>/ 已保留在项目根"
```

### 情形 3：Planner / Verifier / Executor 反复引入 regression

如果 v2/v3 都有 regression，原因通常是：

- Gatekeeper 没追加事实到 `locks/approved-facts.md` → 改对应 templates/gatekeeper-{plan,test,code}.md 「通过」段
- 被审者修订时没 Read locks/ → 改对应 templates/{planner,verifier,executor}.md「修订指引」
- 锁清单条目过于宽泛 / 模糊 → 让对应 Gatekeeper 在追加时写得更具体（含 file:line / 字段名 / 签名）

### 情形 4：实际任务体量远小于估计

如发现整个任务实际不到 1 工作日：

```
1. SendMessage shutdown_request 给所有 teammate（6 个）
2. TeamDelete()
3. 询问用户是否删除 .multi-agent/<team>/（任务已退化）
4. main agent 直接做
5. 向用户报告：
   "经评估，本任务实际体量约 {N} 小时，multi-agent 协作开销不划算（TeamCreate / 6 teammate / 反复 peer DM）。
   我将直接实施。"
```

### 情形 5：teammate 误把消息发给 main agent 而不是同伴

实战中可能发生：Gatekeeper 反馈本应发给 Planner，却误发给 main agent 让转发。处理：

- main agent 收到后**不要直接转发**——这会让 Gatekeeper 误以为 main 仍在循环里
- 立即 SendMessage 给该 Gatekeeper：「请直接发给 planner，peer DM 协议见 templates/gatekeeper-plan.md」
- 同时把原反馈 SendMessage 给 planner，标注「Gatekeeper 误发，我转给你」

这种情况若反复发生，说明 prompt 里 Team 协作协议段不够醒目，需要加固 templates。

### 情形 6：用户主动说"续接"但 .multi-agent/<team>/ 不存在或损坏

```
- main agent 检查：facts.md / locks/approved-facts.md 是否存在且非空
- 缺失 → 告知用户："未找到 .multi-agent/<team>/ 或目录损坏。无法自动续接。可选：
  (a) 提供 facts.md 的备份手动重建；
  (b) 重新走完整流程（Step 1 重新建 facts.md）；
  (c) 直接基于 git log 在新 team_name 下重新走流程"
```
