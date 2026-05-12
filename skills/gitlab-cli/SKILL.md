---
name: gitlab-cli
description: 高效使用 GitLab CLI (glab) 完成 GitLab 相关的所有操作，覆盖合并请求 (MR)、CI/CD 流水线、Issue、仓库管理，重点支持自托管 GitLab 多实例场景。触发场景：用户提到 GitLab、MR、合并请求、流水线、pipeline、glab、CI 状态、审批合并、提个 MR、看下 CI、查 issue、self-hosted GitLab，或者当前仓库的 git remote 指向 gitlab 域名。即使用户没明说 "用 glab"，只要任务涉及 GitLab 仓库的查询和操作，都应优先使用此 skill 走命令行，而不是引导用户去网页点击。
---

# gitlab-cli

GitLab 上所有命令行能搞定的事，都用 `glab` 解决。比起让用户切到浏览器手点，命令行更快、可脚本化、不会跳出当前心流。

## 何时使用

- 当前仓库的 `git remote -v` 包含 GitLab 域名（gitlab.com 或自托管）
- 用户提到 MR / 合并请求 / pipeline / 流水线 / artifact / runner / GitLab issue
- 用户要"提个 MR""审一下""看 CI 跑没跑过""把流水线 retry 下"
- 操作目标是 GitLab，但用户没明说工具名

不进入：纯本地 git 操作（commit、rebase、stash），或仓库托管在 GitHub / Gitea / Bitbucket。

## 前置检查

执行任何 glab 命令前先确认环境就绪，避免连环报错：

```powershell
glab --version           # 1. 确认装好
glab auth status         # 2. 确认认证（最关键）
```

`glab auth status` 没有输出对应主机的 "Logged in" 信息时，说明该主机还没认证，**先引导用户 `glab auth login`，不要自己尝试越权操作**。

仓库识别：默认从当前目录的 git remote 解析项目。跨项目用 `-R/--repo OWNER/REPO`，例如 `glab mr list -R group/sub/project`。

**自托管场景（HTTP 协议、自签证书、多 host）→ 读 `references/self-hosted.md`**。

## 决策思维：什么时候用 glab，什么时候不用

`glab` 是 GitLab REST API 的命令行壳。能用 API 干的事它都能干，但不是所有事都适合走它：

| 场景 | 用什么 | 原因 |
|------|--------|------|
| 提 MR、看 MR、合并、审批、评论 | `glab mr` | 比开浏览器+搜+点快一个数量级 |
| 看 CI 状态、看日志、retry job | `glab ci` | 在终端就能看完整 trace |
| 触发 pipeline、传变量 | `glab ci run` | 可脚本化，参数化 |
| 看/改 Issue、添加评论 | `glab issue` | 不用切窗口 |
| 跨项目、未封装的 REST 操作 | `glab api` | 比 curl 省去 token 管理 |
| 普通 git 操作（commit/push/rebase） | `git` | glab 不是 git 的替代 |
| 复杂 web hook 配置、UI-heavy 设置 | 浏览器 | 命令行参数太多反而慢 |
| Code review 需要看代码 + 反复评论 | 浏览器 | 多窗口对照效率高 |

**核心原则**：能在终端一行解决的，就不要让用户切到浏览器；但不为了用 glab 而用 glab，超过 5 个参数的命令往往说明该走 web 了。

## 高频命令一行流（最常用）

```powershell
# MR
glab mr create --fill                                # 提 MR（用最近 commit 自动填）
glab mr list --reviewer @me                          # 让我评审的
glab mr checkout 123                                 # 拉 MR 到本地
glab mr merge 123 --squash --remove-source-branch    # 合并 + 删源分支
glab mr merge 123 --when-pipeline-succeeds           # 等 CI 过自动合

# CI
glab ci status                                       # 当前分支 pipeline 状态
glab ci trace                                        # 交互选 job 看日志
glab ci retry <job-id>                               # 重试单个 job
glab ci lint                                         # 校验 .gitlab-ci.yml

# Issue
glab issue list --assignee @me
glab issue note 42 -m "已在 !123 修复"

# 万能 API
glab api -h <host> --paginate "/groups/<group>/merge_requests?scope=created_by_me&state=opened&per_page=100"
```

详细参数和用法见 References。

## References 索引

按需读取，不要一次全读：

| 文件 | 何时读取 |
|------|---------|
| `references/self-hosted.md` | 自托管 GitLab 多实例、HTTP 协议、自签证书、host 切换 |
| `references/mr-workflow.md` | MR 完整命令（create/checkout/diff/merge/approve/note/update 等） |
| `references/ci-pipeline.md` | CI/CD 完整命令（status/trace/run/retry/lint/artifact） |
| `references/issue-and-repo.md` | Issue、Repo、Snippet、Release、Variable、Schedule |
| `references/api-and-jq.md` | `glab api` 高级用法 + `jq` 后处理（跨项目批量、CSV 导出、scope 参数） |
| `references/flag-cheatsheet.md` | 怀疑某个 flag 是否真实存在时（避免编造） |

不在表里的能力，先 `glab <command> --help` 看封装；没有再走 `glab api` 配 REST API 文档（https://docs.gitlab.com/ee/api/）。

## 推荐 alias

`glab` 自带 alias 系统，把高频命令别名化能省大量按键：

```powershell
glab alias set mrc 'mr create --fill'
glab alias set mrl 'mr list --reviewer @me'
glab alias set mrm 'mr merge --squash --remove-source-branch'
glab alias set cis 'ci status'
glab alias set cit 'ci trace'
glab alias list
```

更多 alias 建议见 `references/mr-workflow.md` 末尾。

## 常见坑 Top 3

1. **自托管 host 不通**：90% 是 default host 错了或协议错了。`glab config get host` 检查；HTTP 实例要 `glab config set -h <host> api_protocol http`；详见 `references/self-hosted.md`。
2. **flag 报 unknown**：可能是版本太老（`glab check-update`），也可能是编造的 flag（查 `references/flag-cheatsheet.md` 或 `<command> --help`）。
3. **MR 编号是 IID（项目内）不是 ID（全局）**。命令里 `123` 默认是 IID，和 web URL 里的 `/-/merge_requests/123` 一致。跨项目用 `glab api` 时返回的 `iid`/`id` 字段含义不同，看清楚。
