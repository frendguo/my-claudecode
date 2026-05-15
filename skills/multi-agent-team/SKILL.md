---
name: multi-agent-team
description: |
  调度六角色多 agent 团队（Planner + Verifier + Executor + 三 Gatekeeper：plan/test/code）协作完成大型工程任务。所有过程产出落盘到项目内 .multi-agent/<team>/，支持会话续接并节省消息体 token。Gatekeeper 拆为三个阶段专属实例避免上下文膨胀；通过 locks/approved-facts.md 跨阶段共享"已通过事实锁清单"防 regression。范围决策前置避免无效迭代。

  仅通过 /multi-agent-team 命令显式调用（不自动触发）。适用场景：
  - 任务体量 ≥ 3 工作日的 issue / feature / 重构 / 系统改造 / 大型迁移
  - 用户给出 GitLab / GitHub issue 链接并要求"完整实现 / 全部实现 / 从头做"
  - 需要 Planner + Verifier + Executor + Gatekeeper 角色分工、计划与执行分离、独立审查把关的大型工程任务

  不适用于：单文件 bug 修复、< 1 工作日的小改动、没有清晰验收标准的探索性工作、纯调研类问题。
disable-model-invocation: true
---

# Multi-Agent Team Workflow

用 Planner / Verifier / Executor + 三个阶段专属 Gatekeeper（plan / test / code）协作完成大型任务。

**核心机制**：
- TeamCreate 让六个角色加入同一团队
- 所有阶段产出落盘到 `<项目根>/.multi-agent/<team>/`
- 三 Gatekeeper 各管一个阶段，跨阶段通过 `locks/approved-facts.md` 共享事实锁清单
- 通信纪律：SendMessage 只发摘要+artifact 路径，不在消息体里 dump 全文（节省 60-80% 传递 token）

main agent 不当传话筒——它只负责调研建 facts.md、TeamCreate、起 teammate、范围决策、卡点裁决、最终汇报+TeamDelete。Gatekeeper 们常驻 idle 等通知，对各自阶段成果负责。

## Quick Start

最小可运行流程是 7 步。完整步骤见 [examples/full-walkthrough.md](examples/full-walkthrough.md)。

1. **建 facts.md**：创建 `.multi-agent/<team>/` 目录 → main agent 自己读 issue + grep 现有实现 → 写 facts.md（≥10 条 file:line 锚点）。**不要交给 teammate 做**
2. **`TeamCreate({team_name, description})`**：创建团队与共享 task list
3. **同条消息内并行起 6 个 teammate**：每个 `Agent` 调用都带 `team_name + name + subagent_type`，prompt 取自 `templates/`（见下方《Prompt 模板与文件导航》，不要手写）。三个 Gatekeeper 创建为 idle；Planner 直接带 v1 任务启动；Verifier/Executor 起 idle
4. **Planner 写 plan/v1.md → SendMessage(gatekeeper-plan, 摘要+路径)**：gatekeeper-plan 自己 Read 路径，审完写 plan/v1-review.md 并 SendMessage 摘要+路径给 planner（最多 3 轮）
5. **gatekeeper-plan 通过后**：copy 终版到 plan/FINAL.md，追加新通过事实到 locks/approved-facts.md，SendMessage GO 给 main agent → main agent 立刻 AskUserQuestion 范围决策，写 decisions/scope.md
6. **Verifier ↔ gatekeeper-test ↔ Executor ↔ gatekeeper-code**：全程 peer DM；每个产出先落盘再发摘要+路径
7. **全部 Phase 完成 → main agent shutdown_request 给 6 个 teammate → TeamDelete → 复盘**（.multi-agent/ 保留，由用户决定是否 .gitignore / git track / 删除）

## 角色总览

| 角色 | subagent_type | name | 主要 peer DM 对象 | 权限 | artifact 输出 |
|------|---------------|---|---|------|------|
| Planner | `Plan` | `planner` | `gatekeeper-plan` | 只读 | `plan/v{N}.md` |
| Verifier | `general-purpose` | `verifier` | `gatekeeper-test` | 只读 | `test/v{N}.md` |
| Executor | `general-purpose` | `executor` | `gatekeeper-code` | 读写 | `code/phase-N/v{R}.md` + git commit |
| gatekeeper-plan | `general-purpose` | `gatekeeper-plan` | `planner` + main agent (GO) | 只读 | `plan/v{N}-review.md`, 追加 `locks/approved-facts.md` |
| gatekeeper-test | `general-purpose` | `gatekeeper-test` | `verifier` + main agent | 只读 | `test/v{N}-review.md`, 追加 `locks/approved-facts.md` |
| gatekeeper-code | `general-purpose` | `gatekeeper-code` | `executor` + main agent | 只读 | `code/phase-N/review-v{R}.md`, 追加 `locks/approved-facts.md` |

**main agent 的职责**（不在 team 内，是 team 的外部调度者）：
- 建 `.multi-agent/<team>/` + 写 `facts.md`（**唯一不可委派的工作**）
- TeamCreate + 起 6 个 teammate + 派初始任务
- 监听三个 Gatekeeper 的 GO 通知与卡点告警
- 范围决策 AskUserQuestion + 写 `decisions/scope.md`
- Phase 派单 + 滚动派下一 Phase
- 全部 Phase 完成后 shutdown_request + TeamDelete

## Prompt 模板与文件导航

起 teammate 的 prompt **不要手写**——`templates/` 下有每个角色的成稿模板，照填 `{{占位符}}` 即可。所有文件均从本 SKILL.md 一级直达，需要时整文件读取：

| 文件 | 何时读 |
|------|--------|
| [templates/planner.md](templates/planner.md) | 起 `planner` 前——v1 初版 Prompt + 修订指引 |
| [templates/verifier.md](templates/verifier.md) | 派 `verifier` 任务前——测试方案 Prompt + 修订指引 |
| [templates/executor.md](templates/executor.md) | 派 `executor` Phase 任务前——实施 Prompt + commit 规范 + 滚动派单 |
| [templates/gatekeeper.md](templates/gatekeeper.md) | 起任一 Gatekeeper 前**先读**——三者共性协议、反馈结构、审查纪律、占位符 |
| [templates/gatekeeper-plan.md](templates/gatekeeper-plan.md) | 起 `gatekeeper-plan` 前——初始化 Prompt + 模式 A 审查步骤 |
| [templates/gatekeeper-test.md](templates/gatekeeper-test.md) | 起 `gatekeeper-test` 前——初始化 Prompt + 模式 B 审查步骤 |
| [templates/gatekeeper-code.md](templates/gatekeeper-code.md) | 起 `gatekeeper-code` 前——初始化 Prompt + 模式 C 审查步骤 |
| [examples/full-walkthrough.md](examples/full-walkthrough.md) | 需要完整调度演练、失败回退、会话续接示例时 |

## 持久化 artifacts

所有过程产出落盘到 `<项目根>/.multi-agent/<team>/`。这是会话续接基础，也让 SendMessage 只发摘要+路径节省 token。

```
.multi-agent/<team>/
├── facts.md                 # main agent 的事实锚点清单（基线）
├── locks/
│   └── approved-facts.md    # 跨阶段累积"已通过事实锁清单"
├── decisions/
│   └── scope.md             # AskUserQuestion 范围决策结果
├── plan/
│   ├── v1.md, v1-review.md, v2.md, v2-review.md, ...
│   └── FINAL.md             # 通过版本（copy 自最终 v{N}.md）
├── test/
│   └── v1.md, v1-review.md, ..., FINAL.md
└── code/
    └── phase-N/
        ├── v1.md, review-v1.md, v2.md, review-v2.md, ...
        └── FINAL.md         # 含 commit hash + 最终审查结论
```

**写入责任**：

| 文件 | 写者 |
|---|---|
| `facts.md`, `decisions/scope.md` | main agent |
| `plan/v{N}.md` | Planner |
| `test/v{N}.md` | Verifier |
| `code/phase-N/v{R}.md` | Executor（实施报告 + commit hash；代码本身在工作目录由 git 管） |
| `*-review.md`, `FINAL.md`, `locks/approved-facts.md` 追加 | 对应 Gatekeeper |

**目录创建/清理**：
- main agent 在 Step 1 mkdir
- TeamDelete 后**保留** `.multi-agent/<team>/`，用户自行决定 `.gitignore` / `git add` / 删除
- 不主动写 `.gitignore`，尊重用户项目习惯
- 多 team 并存：每个 team 独立子目录

## 通信纪律（token 优化）

### A. SendMessage 只发摘要 + 路径

任何 teammate 完成产出后，先把内容写入 artifact 文件，SendMessage 消息体只带：

```
{阶段} {版本} 已完成。
artifact: .multi-agent/<team>/{path}
摘要：{3-5 行核心变更/产出概要}
{若是修订} 已处理上轮 P0/P1/P2：{N} 项
```

接收方自己 Read 路径获取详细内容。**禁止**把 plan / 审查报告 / 测试矩阵 / 代码 dump 进消息体。

### B. 锁清单外存只发增量

Gatekeeper 反馈的「已通过事实锁清单」段格式：

```
## 已通过事实（详见 .multi-agent/<team>/locks/approved-facts.md，本轮新增 {N} 条）
- {本轮新追加事实 1，带阶段标签如 [plan]}
- {本轮新追加事实 2}
（已存档 {K} 条不在此重列）
```

Gatekeeper 通过审查时**追加**新事实到 `locks/approved-facts.md`（不覆盖）。后续 Gatekeeper 启动时 first action 是 Read 该文件。

### C. 起步 prompt 用文件引用替代内嵌

起 teammate 时 prompt 中**不内嵌** facts/plan/test 全文，改写路径：

```
## 已建立的事实锚点
请 Read .multi-agent/<team>/facts.md 获取（main agent 已核实，请基于这些事实做计划，不要自行重新调研改写）。
```

teammate 在 first action 自行 Read。模板里 `{{ACK_FACTS}}` `{{APPROVED_PLAN}}` 等占位符填写改为 artifact 路径。

## 会话续接

会话被中断后，**用户主动提及**才续接（如"继续上次的 team-X" / "续上次的 issue-1 多 agent 任务"）。main agent 不自动扫描 `.multi-agent/` 目录。

**用户主动续接的处理流程**：
1. main agent 确认 `.multi-agent/<team>/` 存在
2. Read `facts.md`, `decisions/scope.md`, `locks/approved-facts.md`，以及 `plan/FINAL.md`, `test/FINAL.md`（如已存在）
3. 用 `git log --grep="Phase"` 确定已完成的 Phase
4. 检查 `code/phase-N/` 目录确定当前进度
5. AskUserQuestion 确认续接点（如"上次进度：Phase 0/1 已通过，Phase 2 写到 v1 但未通过审查。从 Phase 2 v2 修订续接？"）
6. TeamCreate 同名 team（如已 TeamDelete 则新建）+ 起 6 个 teammate；Gatekeeper 起步时 Read locks/ 重建基线
7. 派任务时引用 artifact 路径，不内嵌内容

**为什么不自动续接**：用户可能在两次会话之间手动改了代码 / 调整了 plan，自动恢复反而错位。让用户显式表明意图。

## 五条经验法则

每条对应真实踩过的坑。理解 **为什么** 比死记规则重要——遇到边界情况时凭原理判断。

### 法则 1：同一阶段内复用 teammate，修订不开新 Agent

**做法**：plan 阶段全程用同一个 `planner` teammate，test 阶段同一个 `verifier`，每个 Phase 同一个 `executor`。**任何角色都不应在同一阶段的修订循环中重新 Agent 一个新 teammate**。

**例外（非违反）**：阶段切换时三个 Gatekeeper 是不同实例，这是设计如此——每个 Gatekeeper 启动时通过 Read `locks/approved-facts.md` 重建跨阶段事实基线。

**为什么**：同阶段开新 teammate 是 fresh context，看不到本阶段已通过的事实，容易"改错回去"（regression）。Team 内 teammate 命名空间固定，重复命名行为未定义。

**跳过的后果**：实战中曾发生 v1→v2 时 Planner 把已通过的 3 个配置 key 改成虚构名，又花 2 轮才修回来。

### 法则 2：已通过事实锁清单跨阶段共享在 locks/approved-facts.md

**做法**：
- 每个 Gatekeeper 通过审查时 **追加** 本轮新通过事实到 `locks/approved-facts.md`（不覆盖），每条带阶段标签 `[plan]` / `[test]` / `[code-phase-N]`
- 后续 Gatekeeper 启动时 first action 是 Read 该文件
- Gatekeeper 给被审者的反馈消息按通信纪律 B 列出**本轮新增**事实，引用文件获取完整清单

**为什么**：跨阶段一致性的唯一可靠媒介。即便同阶段 teammate 复用 context，反馈里如果只列"要改什么"而不列"不能动什么"，被反馈者仍可能在改动相邻段落时连锁修改已通过部分。Peer DM 模式下 main agent 不在循环里，没人会兜底。三 Gatekeeper 拆分后这点更关键，plan 阶段通过的事实必须传到 code 阶段。

**跳过的后果**：参见法则 1 的事故。三 Gatekeeper 不读 `locks/` 会导致 code 阶段把 plan 阶段确认的契约改错。

### 法则 3：范围决策前置到 Planner v1 之后

**做法**：gatekeeper-plan 通过 Planner v1 后向 main agent 发 GO 通知，main agent **立刻** AskUserQuestion 问"本次会话推进到哪几个 Phase？"，结果写入 `decisions/scope.md`。后续 gatekeeper-test / gatekeeper-code 审查只聚焦用户选定范围。

**为什么**：大型任务（20+ 工作日）单会话物理做不完。先选定范围再迭代，可以让 Gatekeeper 把审查精力放在确实要做的部分。

**跳过的后果**：实战中曾在 23d 完整范围上做了 4 轮 Plan 审查迭代，结果用户最后选了"做前 3 个 Phase 即可"——后面 3 轮审查浪费了。

### 法则 4：每个 Phase 完成立刻写 artifact + git commit

**做法**：Executor 通过 gatekeeper-code 审查后顺序：跑测试 → 写 `code/phase-N/v{R}.md`（实施报告 + commit hash） → `git commit` → SendMessage 通知。commit message 带 Phase 编号。Gatekeeper 审查时跑 `git log` 能看到提交点。通过后 gatekeeper-code copy 该 v{R}.md 到 `code/phase-N/FINAL.md`。

**为什么**：大任务会话总是会超出 token 预算；提前 commit + artifact 保证"会话被打断也不丢工作"，下次会话靠 `.multi-agent/` + git log 续接。

**跳过的后果**：Phase 0+1+2 全部完成才 commit 万一中间会话耗尽则前面工作不保；或 commit 了但没 artifact 新会话无法理解决策上下文。

### 法则 5：Verifier 设计与 Phase 0 脚手架可并行

**做法**：如果 Phase 0 是无业务依赖的脚手架（sln / csproj / 目录骨架），main agent **同一条消息**内分别 SendMessage 给 Verifier 和 Executor 派任务。两者完成后各自通知对应 Gatekeeper（gatekeeper-test / gatekeeper-code）。

**为什么**：测试方案设计不依赖代码，脚手架不依赖测试方案，强行串行白白消耗 wall-clock 时间和 token。Team 内多个 teammate 并行 active 时，两个 Gatekeeper 各自处理审查请求互不干扰。

**何时不并行**：Phase 0 涉及业务逻辑选择、或 Verifier 输出会影响 Phase 0 文件结构时，仍须串行。

## Team 生命周期

```
mkdir .multi-agent/<team>/  (main agent)
   ↓
写 facts.md  (main agent)
   ↓
TeamCreate({team_name, description})
   ↓                                                 ~/.claude/teams/{name}/config.json
                                                     ~/.claude/tasks/{name}/
[同条消息并行起 6 个 teammate]
Agent({team_name, name: "gatekeeper-plan", subagent_type: "general-purpose", prompt: <模板>})
Agent({team_name, name: "gatekeeper-test", ...})
Agent({team_name, name: "gatekeeper-code", ...})
Agent({team_name, name: "planner", subagent_type: "Plan", prompt: <带 v1 任务>})
Agent({team_name, name: "verifier", ...})
Agent({team_name, name: "executor", ...})
   ↓
[Peer DM 协作期]
SendMessage({to: <name>, message: 摘要+路径, summary})  - 任意 teammate 互发
TaskUpdate({taskId, status, owner})                    - 共享 task list 协调
（artifact 写入 .multi-agent/<team>/）
   ↓
[收尾]
SendMessage({to: <name>, message: {type: "shutdown_request"}}) × 6
   ↓
TeamDelete()  → ~/.claude/teams/, ~/.claude/tasks/ 清理
.multi-agent/<team>/ 保留（用户处置）
```

### Peer DM 协议要点

- **发现 teammate**：任何 teammate 可 Read `~/.claude/teams/{team-name}/config.json` 获取所有 members 的 `name`。**总是用 name 而不是 agentId 来 SendMessage**。
- **plain text 通信**：正常文字消息，next turn 自动送达对方。`summary` 字段是 5-10 词的预览（必填）。
- **artifact 引用替代消息体**：通信纪律 A——任何完成的产出先落盘 `.multi-agent/<team>/`，SendMessage 只发摘要+路径
- **不要发结构化状态 JSON**：别发 `{type: "idle"}` `{type: "task_completed"}` 之类——idle 是系统自动通知，task 完成用 `TaskUpdate` 标
- **shutdown 协议**：收到 `{type: "shutdown_request"}` → 回 `{type: "shutdown_response", request_id, approve: true}`，approve=true 会终止该 teammate 进程
- **Idle ≠ 离线**：每个 teammate 每个 turn 结束都会 idle 并发系统通知，但仍可被新 SendMessage 唤醒。不要把 idle 当错误处理
- **任务认领**：用 `TaskUpdate({taskId, owner: "<my-name>"})` 自行接派

## TaskCreate 命名规范

| 任务 | subject 示例 | owner 示例 |
|------|-----------|---|
| 1 | `Plan: Planner 产出 v1` | `planner` |
| 2 | `Plan: gatekeeper-plan 审 v1` | `gatekeeper-plan` |
| 3 | `Plan: 范围决策（AskUser）` | （main agent，不在 team 中）|
| 4 | `Test: Verifier 设计测试方案` | `verifier` |
| 5 | `Test: gatekeeper-test 审测试方案` | `gatekeeper-test` |
| 6 | `Code: Phase N 实施` | `executor` |
| 7 | `Code: Phase N 审查` | `gatekeeper-code` |

## 工作流检查清单

跑完一轮多 agent 流程时把以下清单复制到对话中，逐项打勾。

```
Multi-Agent Team Progress:
- [ ] mkdir .multi-agent/<team>/ + 写 facts.md（≥10 条 file:line）
- [ ] TeamCreate({team_name, description})
- [ ] 同条消息并行起 6 个 teammate（gatekeeper-{plan,test,code} / planner / verifier / executor）
- [ ] Planner v1 → gatekeeper-plan peer DM 审 → 修订循环（最多 3 轮）→ plan/FINAL.md
- [ ] AskUserQuestion 范围决策（收到 GO 通知后）→ 写 decisions/scope.md
- [ ] Verifier 测试方案 → gatekeeper-test peer DM 审 → test/FINAL.md
- [ ] (可选) Phase 0 脚手架与 Verifier 并行
- [ ] Phase N Executor 实施 + commit + 写 code/phase-N/v{R}.md → gatekeeper-code peer DM 审 → 通过 → FINAL.md
- [ ] ... (每 Phase 重复)
- [ ] shutdown_request 给每个 teammate（6 个）
- [ ] TeamDelete()
- [ ] 整体进度汇报 + 复盘（.multi-agent/ 保留与否提示用户）
```

## 何时退出 skill

退出条件比起步条件更重要，避免 multi-agent 流程被误用在不合适的任务上。

- **用户取消或改主意** → 立即给所有 teammate 发 shutdown_request，TeamDelete，问用户是否保留/删除 `.multi-agent/<team>/`，汇报当前进度
- **Gatekeeper 同一处问题 3 轮仍 NO-GO** → 主动 SendMessage 给 main agent 报告卡点；main agent AskUserQuestion 让用户裁决，不要无限循环
- **会话 token 预算告急** → 让 Executor commit 当前所有进度 + 写 `code/phase-N/v{R}.md`，shutdown teammate；告知用户在新会话主动提"续接 team-X"，main agent 会从 `.multi-agent/<team>/` + git log 重建上下文
- **发现实际任务体量 < 1 工作日** → 退出 skill，main agent 直接做。多 agent 协作有固定开销（TeamCreate / 6 teammate / 反复审查），小任务上得不偿失

## 调度示例

完整伪代码 + 真实场景演练见 [examples/full-walkthrough.md](examples/full-walkthrough.md)。该文件包含：

- mkdir + facts.md + TeamCreate + 6 角色并行起步的完整调度顺序
- Peer DM 模式下三 Gatekeeper 的反馈消息示例（含锁清单文件引用）
- main agent 在范围决策、GO 通知、卡点裁决三种节点的处理示例
- shutdown_request × 6 + TeamDelete 收尾流程
- 失败回退处理 + 会话续接示例

## 持续改进

跑完一轮完整流程后简要复盘，把新发现直接更新到本 skill：

- 哪个 Gatekeeper 返工率最高？反馈模板是否需要补强？
- artifact 路径引用是否真实节省消息 token（vs 退化为消息体内嵌）？
- 范围决策是否在合适时机？
- 是否有可并行被串行的步骤？
- locks/approved-facts.md 是否被三个 Gatekeeper 正确读取？
- TaskUpdate owner 字段是否被正确使用？
