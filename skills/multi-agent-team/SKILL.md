---
name: multi-agent-team
description: |
  调度四角色多 agent 团队（Planner 计划 + Gatekeeper 审查 + Verifier 测试设计 + Executor 实施）完成大型工程任务。通过 TeamCreate 让四个角色加入同一团队，使用 Peer DM 直接互相对话——Gatekeeper ↔ Planner / Verifier / Executor 的多轮反馈循环不再经 main agent 中转。Gatekeeper 常驻 idle 审查角色，对最终结果负责。强制「已通过事实锁清单」在修订间保留以防 regression，并把范围决策点前置避免无效迭代。

  以下场景必须使用此 skill，即便用户没明说"多 agent"：
  - 任务体量 ≥ 3 工作日的 issue / feature / 重构 / 系统改造 / 大型迁移
  - 用户给出 GitLab / GitHub issue 链接并要求"完整实现 / 全部实现 / 从头做"
  - 用户提到 multi-agent / 多 agent / agent team / 计划者+执行者+验证者+把关者 / Planner + Gatekeeper / 把关者 任一组合
  - 用户暗示需要"角色分工"，如"一个 agent 计划另一个审查"、"拆给不同 agent 做"、"分工协作"
  - 使用 /multi-agent-team 命令时

  本 skill 不适用于：单文件 bug 修复、< 1 工作日的小改动、没有清晰验收标准的探索性工作、纯调研类问题。
disable-model-invocation: true
---

# Multi-Agent Team Workflow

用 Planner / Gatekeeper / Verifier / Executor 四角色协作完成大型任务。

**核心机制**：通过 `TeamCreate` 让四个角色加入同一团队，Gatekeeper ↔ 其他三角色之间通过 **Peer DM** 直接对话。main agent 不再当传话筒——它只负责调研事实、TeamCreate、起 teammate 并派初始任务、在用户决策节点出场（范围 / 卡点裁决）、最终汇报 + TeamDelete。Gatekeeper 不参与产出，常驻 idle 等待通知，对最终结果负责。

本 skill 的内容来自一次真实的大型扩展开发复盘——记下了哪些坑在多 agent 协作中最容易踩，以及对应的预防机制。早期版本用「spawn-and-name + main agent 转手」模式，反馈循环里 main agent 每轮消耗大量 token 重复消息内容；本版本改用 Team + Peer DM，main agent 只在节点出现。

## Quick Start

最小可运行流程是 6 步。完整步骤见 [examples/full-walkthrough.md](examples/full-walkthrough.md)。

1. **建事实锚点清单**：main agent 自己读 issue + grep 现有实现，记录 N 条带 file:line 的事实。这是后续 Gatekeeper 审查的基线，**不要交给 sub-agent 做**
2. **`TeamCreate({team_name, description})`**：创建团队与共享 task list
3. **同条消息内并行起 4 个 teammate**：每个 `Agent` 调用都带 `team_name + name + subagent_type`。Gatekeeper 先创建好常驻 idle；Planner 直接带 v1 任务启动；Verifier / Executor 起 idle 等通知
4. **Planner v1 完成 → 直接 SendMessage 给 Gatekeeper**：Planner 完成产出后**自己** SendMessage 通知 Gatekeeper，**不经 main agent**。Gatekeeper 审完直接 SendMessage 给 Planner 修订（最多 3 轮）
5. **AskUserQuestion 范围决策**：Gatekeeper 通过 Planner 终版后给 main agent 发 GO 通知，main agent 立刻问推进范围
6. **Verifier → Gatekeeper → Executor → Gatekeeper** 全程 peer DM，main agent 只在用户决策点和 GO 通知到达时出现。全部 Phase 完成 → main agent `SendMessage({type: "shutdown_request"})` 关停 teammate → `TeamDelete()` 清理

## 角色总览

| 角色 | subagent_type | team 内 name | Peer DM 对象 | 权限 | 产出 |
|------|---------------|---|---|------|------|
| Gatekeeper | `general-purpose` | `gatekeeper` | 接收三角色的产出通知，直接回反馈给原作者；通过后通知 main agent | 只读 | P0/P1/P2 审查报告 |
| Planner | `Plan` | `planner` | 完成产出通知 Gatekeeper；接收 Gatekeeper 反馈直接修订并回发 | 只读 | Phase 拆分 + 锚点 |
| Verifier | `general-purpose` | `verifier` | 完成产出通知 Gatekeeper；接收反馈直接修订并回发 | 只读 | 测试矩阵 |
| Executor | `general-purpose` | `executor` | 每 Phase commit 后通知 Gatekeeper；接收反馈直接修订并回发 | 读写 | 代码 + 测试 + commit |

**main agent 的职责**（不在 team 内，是 team 的外部调度者）：
- 调研建事实锚点清单（**唯一一项不可委派的工作**）
- TeamCreate + 起 4 个 teammate + 派初始任务
- 监听 Gatekeeper 的 GO 通知与卡点告警
- 在节点 AskUserQuestion 做范围决策
- 全部 Phase 完成后 shutdown_request + TeamDelete + 复盘

## 标准流程

```
[1] main agent 调研 → 建事实锚点清单
        ↓
[2] TeamCreate({team_name, description})
        ↓
[3] 同条消息内并行起 4 个 teammate（每个 Agent 调用都带 team_name）：
    - gatekeeper（idle 等通知）
    - planner（带 v1 任务直接启动）
    - verifier（idle）
    - executor（idle）
        ↓
[4] planner 完成 v1 → SendMessage(gatekeeper) → 审 → SendMessage(planner) 反馈 → …
    peer DM 循环（最多 3 轮）main agent 不参与
        ↓ 通过
[5] gatekeeper SendMessage(main agent 名/team-lead) 发 GO 通知
        ↓
[6] main agent: AskUserQuestion 范围决策
        ↓
[7] main agent SendMessage(verifier) 派任务 → verifier ↔ gatekeeper peer DM 循环
        ↓ 通过 → gatekeeper 通知 main agent
[8] main agent SendMessage(executor) 派 Phase N → executor 实施 + commit
    → executor SendMessage(gatekeeper) 触发审 → peer DM 循环
        ↓ 通过 → gatekeeper 通知 main agent
[9] main agent 派下一 Phase（循环 step 8）
        ↓ 全部 Phase 完成
[10] main agent SendMessage({type: "shutdown_request"}) 给每个 teammate
     → TeamDelete() → 复盘
```

## 五条经验法则

每条都对应一个真实踩过的坑。理解 **为什么** 比死记规则重要——遇到边界情况时凭原理判断。

### 法则 1：team 内复用 teammate，修订不开新 Agent

**做法**：第一次起 Planner 时用 `Agent({team_name, name: "planner", subagent_type: "Plan", prompt})` 加入团队。后续 Gatekeeper 反馈一律 `SendMessage({to: "planner", message})`，Planner 收到反馈后修订并 SendMessage 回 Gatekeeper。**任何角色都不应在修订循环中重新 Agent 一个新 teammate**。

**为什么**：
- 新开的 teammate 是 fresh context，看不到 v1 已经核实通过的事实锚点，容易把已通过的事实"改错回去"（regression）
- Team 内 teammate 命名空间固定，重复命名行为未定义；不重名又会导致协作图谱混乱

**跳过的后果**：实战中曾发生 v1→v2 时 Planner 把已通过的 3 个配置 key 改成虚构名，又花 2 轮才修回来。

### 法则 2：Gatekeeper 反馈顶部强制"已通过事实锁清单"

**做法**：Gatekeeper 给原作者（Planner / Verifier / Executor）的反馈消息第一段必须是「## 已通过事实（禁止改动）」，逐条列出 file:line 锚点。详见 [templates/gatekeeper.md](templates/gatekeeper.md)「反馈格式」。

**为什么**：即便 teammate 复用同一上下文，反馈里如果只列"要改什么"而不列"不能动什么"，被反馈者仍可能在改动相邻段落时连锁修改已通过部分。Peer DM 模式下 main agent 不在循环里，更没人会兜底——锁清单是唯一防线。

**跳过的后果**：参见法则 1 的事故。

### 法则 3：范围决策前置到 Planner v1 之后

**做法**：Gatekeeper 通过 Planner v1 后向 main agent 发 GO 通知，main agent **立刻** AskUserQuestion 问"本次会话推进到哪几个 Phase？"。后续 Gatekeeper 审查只聚焦用户选定范围。

**为什么**：大型任务（20+ 工作日）单会话物理做不完。先选定范围再迭代，可以让 Gatekeeper 把审查精力放在确实要做的部分，避免在 4-5 周后续 Phase 上反复磨细节。

**跳过的后果**：实战中曾在 23d 完整范围上做了 4 轮 Plan 审查迭代，结果用户最后选了"做前 3 个 Phase 即可"——后面 3 轮审查浪费了。

### 法则 4：每个 Phase 完成立刻 git commit

**做法**：Executor 模板里硬性要求每个 Phase 通过 Gatekeeper 审查后，先 `git commit` 再开始下一 Phase。commit message 带 Phase 编号。Executor 在 SendMessage 通知 Gatekeeper 之前**先 commit**——Gatekeeper 审查时跑 `git log` 能看到提交点。

**为什么**：大任务会话总是会超出 token 预算；提前 commit 保证"会话被打断也不丢工作"，下次会话从 commit 状态续接。

**跳过的后果**：实战中 Phase 0+1+2 全部完成才 commit，万一中间会话耗尽则前面工作不保。

### 法则 5：Verifier 设计与 Phase 0 脚手架可并行

**做法**：如果 Phase 0 是无业务依赖的脚手架（sln / csproj / 目录骨架），main agent **同一条消息**内分别 SendMessage 给 Verifier 和 Executor 派任务。两者完成后各自通知 Gatekeeper 审查（也是 peer DM）。

**为什么**：测试方案设计不依赖代码，脚手架不依赖测试方案，强行串行白白消耗 wall-clock 时间和 token。Team 内多个 teammate 并行 active 时，Gatekeeper 可以排队处理审查请求。

**何时不并行**：Phase 0 涉及业务逻辑选择、或 Verifier 输出会影响 Phase 0 文件结构时，仍须串行。

## Team 生命周期

```
TeamCreate({team_name, description})
   ↓                                                 ~/.claude/teams/{name}/config.json (members)
                                                     ~/.claude/tasks/{name}/ (共享 task list)
[同条消息并行]
Agent({team_name, name: "gatekeeper", subagent_type: "general-purpose", prompt: <模板 idle 准备>})
Agent({team_name, name: "planner", subagent_type: "Plan", prompt: <带 v1 任务>})
Agent({team_name, name: "verifier", subagent_type: "general-purpose", prompt: <idle 准备>})
Agent({team_name, name: "executor", subagent_type: "general-purpose", prompt: <idle 准备>})
   ↓
[Peer DM 协作期]
SendMessage({to: <name>, message, summary})   - 任意 teammate 互发
TaskUpdate({taskId, status, owner})           - 共享 task list 协调
   ↓
[收尾]
SendMessage({to: <name>, message: {type: "shutdown_request"}})  - 对每个 teammate
   ↓
TeamDelete()                                  - 删除 team 目录 + task 目录
```

### Peer DM 协议要点

- **发现 teammate**：任何 teammate 可 Read `~/.claude/teams/{team-name}/config.json` 获取所有 members 的 `name`。**总是用 name 而不是 agentId 来 SendMessage**。
- **plain text 通信**：正常文字消息，next turn 自动送达对方。`summary` 字段是 5-10 词的预览（必填）。
- **不要发结构化状态 JSON**：别发 `{type: "idle"}` `{type: "task_completed"}` 之类——idle 是系统自动通知，task 完成用 `TaskUpdate` 标。
- **shutdown 协议**：收到 `{type: "shutdown_request"}` → 回 `{type: "shutdown_response", request_id, approve: true}`，approve=true 会终止该 teammate 进程。
- **Idle ≠ 离线**：每个 teammate 每个 turn 结束都会 idle 并发系统通知，但仍可被新 SendMessage 唤醒。不要把 idle 当错误处理。
- **任务认领**：用 `TaskUpdate({taskId, owner: "<my-name>"})` 自行接派。Gatekeeper 审查任务通常由 main agent 创建 + 等待，不需要 Gatekeeper 主动认领（除非用模式 C 的 task-list 驱动变种）。

## TaskCreate 命名规范

共享 task list 上所有 teammate 都能看到。每个任务必须有具体 subject + description，方便 teammate 自行接派或被 main agent 指派。

| 任务 | subject 示例 | owner 示例 |
|------|-----------|---|
| 1 | `Plan: Planner 产出 v1` | `planner` |
| 2 | `Plan: Gatekeeper 审 v1` | `gatekeeper` |
| 3 | `Plan: 范围决策（AskUser）` | （main agent，不在 team 中）|
| 4 | `Test: Verifier 设计测试方案` | `verifier` |
| 5 | `Test: Gatekeeper 审测试方案` | `gatekeeper` |
| 6 | `Code: Phase N 实施` | `executor` |
| 7 | `Code: Phase N 审查` | `gatekeeper` |

## 工作流检查清单

跑完一轮多 agent 流程时把以下清单复制到对话中，逐项打勾。这样既帮你不漏步，也让用户清楚看到进度。

```
Multi-Agent Team Progress:
- [ ] 调研 issue + 建事实锚点清单（≥10 条 file:line）
- [ ] TeamCreate({team_name, description})
- [ ] 同条消息并行起 4 个 teammate（gatekeeper / planner / verifier / executor）
- [ ] Planner v1 → Gatekeeper peer DM 审 → 修订循环（最多 3 轮）
- [ ] AskUserQuestion 范围决策（收到 Gatekeeper GO 通知后）
- [ ] Verifier 测试方案 → Gatekeeper peer DM 审
- [ ] (可选) Phase 0 脚手架与 Verifier 并行
- [ ] Phase N Executor 实施 + commit → Gatekeeper peer DM 审 → 通过
- [ ] ... (每 Phase 重复)
- [ ] shutdown_request 给每个 teammate
- [ ] TeamDelete()
- [ ] 整体进度汇报 + 复盘
```

## 何时退出 skill

退出条件比起步条件更重要，避免 multi-agent 流程被误用在不合适的任务上。

- **用户取消或改主意** → 立即给所有 teammate 发 shutdown_request，TeamDelete，汇报当前进度
- **Gatekeeper 同一处问题 3 轮仍 NO-GO** → Gatekeeper 应主动 SendMessage 给 main agent 报告卡点；main agent AskUserQuestion 让用户裁决，不要无限循环
- **会话 token 预算告急** → 让 Executor commit 当前所有进度，shutdown teammate，告知用户在新会话用 `git log` + Team 在 `~/.claude/teams/<name>/` 续接（或新建 Team 接续）
- **发现实际任务体量 < 1 工作日** → 退出 skill，main agent 直接做。多 agent 协作有固定开销（TeamCreate / 4 个 teammate / 反复审查），小任务上得不偿失

## 调度示例

完整伪代码 + 真实场景演练见 [examples/full-walkthrough.md](examples/full-walkthrough.md)。该文件包含：

- TeamCreate + 4 角色并行起步的完整调度顺序
- Peer DM 模式下 Gatekeeper ↔ Planner / Verifier / Executor 的反馈消息示例（含锁清单段）
- main agent 在范围决策、Gatekeeper GO 通知、卡点裁决三种节点的处理示例
- shutdown_request + TeamDelete 收尾流程
- 失败回退处理

## 持续改进

跑完一轮完整流程后简要复盘，向用户报告并把新发现的改进直接更新到本 skill：

- 哪轮 Gatekeeper 返工率最高？反馈模板是否需要补强？
- Peer DM 是否成功（vs Gatekeeper 误发给 main agent）？
- 范围决策是否在合适时机？
- 是否有可并行但被串行的步骤？
- TaskUpdate 的 owner 字段是否被正确使用（teammate 自行接派 vs main 指派）？

发现的模式直接更新 SKILL.md 或对应 template，让下次会话受益。
