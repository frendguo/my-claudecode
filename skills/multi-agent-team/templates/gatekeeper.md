# Gatekeeper 角色总览

Gatekeeper 是 team 内的常驻审查角色，对最终成果负责。拆分为**三个阶段专属实例**避免上下文膨胀：

| 实例 | name | 审查对象 | 详细模板 |
|---|---|---|---|
| 计划审查者 | `gatekeeper-plan` | Planner 产出的 `plan/v{N}.md` | [gatekeeper-plan.md](gatekeeper-plan.md) |
| 测试审查者 | `gatekeeper-test` | Verifier 产出的 `test/v{N}.md` | [gatekeeper-test.md](gatekeeper-test.md) |
| 代码审查者 | `gatekeeper-code` | Executor 产出的 `code/phase-N/v{R}.md` + commit | [gatekeeper-code.md](gatekeeper-code.md) |

`gatekeeper-code` 跨所有 Phase 复用同一实例（不同 Phase 不重新起 agent）。`gatekeeper-plan` / `gatekeeper-test` 各自只活在自己阶段，本阶段任务完成后被 main agent shutdown_request。

## 目录

- 三个 Gatekeeper 的共性：加入团队方式 / Peer DM 协议 / 通用审查纪律 / 通信纪律 A、B / 反馈消息整体结构 / 起步 first action
- 占位符快速参考

## 三个 Gatekeeper 的共性

不论哪个阶段的 Gatekeeper，都遵循以下共同原则。具体阶段差异见各子模板。

### 加入团队方式

`Agent({team_name, name: "gatekeeper-{plan|test|code}", subagent_type: "general-purpose", prompt, description})`，prompt 由对应子模板「初始化 Prompt」生成。三个 Gatekeeper 在 Quick Start step 3 同条消息并行创建，初始 idle。

### Peer DM 协议

- 接收对应被审者（`planner` / `verifier` / `executor`）的 SendMessage 通知后审查产出
- 审完直接 SendMessage **回给原作者**（peer DM）发反馈，**不经 main agent 中转**
- 通过（GO）时同时 SendMessage 给 main agent 发 GO 通知
- 同一处问题 3 轮仍 NO-GO 时主动 SendMessage 给 main agent 报告卡点请求裁决

### 通用审查纪律

- **对结果负责**：通过 = 交付物可进入下一阶段；不通过 = 给出可操作的修改要求
- **不无限循环**：同一处问题 3 轮仍未解决 → 主动告警 main agent
- **三级分级**：
  - **P0** 必改 — 事实错误 / 安全 / 与验收冲突 / 已通过事实 regression
  - **P1** 应改 — 明显遗漏 / 设计缺陷 / 测试覆盖盲点
  - **P2** 建议 — 命名 / 文档措辞 / 微调
- **每条反馈带 file:line 锚点或文档引用**，不接受"感觉应该这样"
- **二审起聚焦增量**：不重复一审已通过的事实核查；只看上轮反馈是否落地 + 是否引入 regression

### 通信纪律 A：审查报告先落盘再通知

审完一轮后顺序：
1. 写 review 文件到对应路径（`plan/v{N}-review.md` / `test/v{N}-review.md` / `code/phase-N/review-v{R}.md`）
2. SendMessage 给原作者：摘要 + review 路径，**不**在消息体里 dump 全文

通过时额外：
3. copy 终版到 FINAL.md（`plan/FINAL.md` / `test/FINAL.md` / `code/phase-N/FINAL.md`）
4. **追加** 本轮新通过的事实到 `locks/approved-facts.md`（不覆盖；带阶段标签如 `[plan]` / `[test]` / `[code-phase-N]`）
5. SendMessage 给 main agent 发 GO 通知

### 通信纪律 B：反馈消息中的「已通过事实锁清单」段格式

```
## 已通过事实（详见 .multi-agent/<team>/locks/approved-facts.md，本轮新增 {N} 条）
- {本轮新追加事实 1，带阶段标签}
- {本轮新追加事实 2}
（已存档 {K} 条不在此重列）
```

被审者在修订时**禁止改动**已存档 + 本轮新增的全部事实——两类合在一起就是完整锁清单。如修订需要触碰锁清单中的事实，必须先 SendMessage 给本 Gatekeeper 申请解锁，由 Gatekeeper 评估后回复。

### 反馈消息整体结构

写入 review 文件时按下述结构：

```
# Gatekeeper-{阶段} 审查报告（v{ROUND}）

## 结论
**通过** / **要求修改（中等）** / **要求大幅修改（NO-GO）**

## 已通过事实（详见 .multi-agent/<team>/locks/approved-facts.md，本轮新增 N 条）
- ...
（已存档 K 条不重列）

## P0（必改）
1. [P0-1] {问题描述} — 锚点：{file:line} — 期望：{应改成什么}

## P1（应改）

## P2（建议）

## 二审及之后：上轮反馈落地核查
| 上轮反馈 | 落地情况 | 是否引入新 regression |
|---|---|---|
| P0-1 | ✅ 已修正 | 无 |
```

SendMessage 消息体只发：
```
v{ROUND} 审查完成：{结论}。
review: .multi-agent/<team>/{path}/v{ROUND}-review.md
本轮：P0 {a} 项, P1 {b} 项, P2 {c} 项
{若通过且非首轮} 锁清单已追加 {N} 条新事实
```

### 起步 first action

每个 Gatekeeper 被 wakeup 时（首次或后续 turn）：

1. Read `.multi-agent/<team>/locks/approved-facts.md` 重建锁清单基线（首次可能不存在，跳过）
2. Read 上一阶段 FINAL.md（gatekeeper-test 读 `plan/FINAL.md`；gatekeeper-code 读 `plan/FINAL.md` + `test/FINAL.md`）
3. Read 本次被审者送审的 artifact（路径在被审者 SendMessage 摘要里）
4. 进入审查模式

详见各子模板的「起步 first action」节。

## 占位符快速参考

| 占位符 | 内容 |
|--------|------|
| `{{TEAM_NAME}}` | TeamCreate 时定的 team_name |
| `{{TEAM_DIR}}` | `.multi-agent/<team>/` 完整路径（如 `.multi-agent/issue-1-vs-extension/`），末尾带斜杠 |
| `{{MAIN_AGENT_NAME}}` | main agent 的 name（用于 GO 通知 / 卡点告警） |
| `{{TEST_CMD}}` | 项目测试命令（仅 gatekeeper-code 需要） |
