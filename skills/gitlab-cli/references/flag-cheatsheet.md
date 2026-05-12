# 易混淆 flag 真伪表

LLM 容易凭语感编造看起来"应该存在"但实际不存在的 flag。怀疑某个 flag 时优先查这张表，或直接 `glab <command> --help` 验证。

## ✅ 真实存在的常用 flag

### glab mr

| flag | 含义 |
|------|------|
| `--fill` | 用最近 commit 自动填标题/正文（mr create） |
| `--draft` | 标记为草稿（mr create） |
| `--label "x,y"` | 加标签（mr create / update） |
| `--unlabel "x"` | 移除标签（mr update） |
| `--assignee @me` | 指派（mr create / list / update） |
| `--reviewer @me` | 评审人（mr create / list / update） |
| `--target-branch <branch>` | 目标分支（mr create） |
| `--squash` | squash 合并（mr merge） |
| `--remove-source-branch` | 合并后删源分支（mr merge） |
| `--rebase` | rebase 合并（mr merge） |
| `--squash-message "..."` | 自定义 squash commit 信息（mr merge） |
| `--when-pipeline-succeeds` | 等 CI 通过自动合（mr merge） |
| `--comments` | 看评论（mr view） |
| `--web` | 浏览器打开（多个子命令） |
| `--state opened/closed/merged/all` | MR 状态筛选（mr list） |
| `--search "..."` | 标题/正文搜索（mr list） |
| `--per-page <n>` | 单页条数（mr list） |
| `--output json` 或 `-F json` | JSON 输出（mr list） |
| `-m / --message` | 评论内容（mr note） |
| `-R / --repo <owner/repo>` | 切仓库（所有子命令） |

### glab ci

| flag | 含义 |
|------|------|
| `--branch <name>` | 指定分支（ci status / list / run） |
| `--status failed` | 状态筛选（ci list），值为 `success/failed/canceled/running/pending/...` |
| `--per-page <n>` | 单页条数（ci list） |
| `--variables KEY:value,K2:v2` | 传变量（ci run） |
| `--path <file>` | 指定 yml 路径（ci lint） |
| `--pipeline <id>` | 指定 pipeline ID（ci get） |

### glab issue

| flag | 含义 |
|------|------|
| `--title "..."` | 标题（issue create） |
| `--description "..."` | 描述（issue create / update） |
| `--label "x"` | 标签（issue create / update） |
| `--unlabel "x"` | 移除标签（issue update） |
| `--milestone "..."` | 里程碑 |
| `--confidential` | 私密 issue（issue create） |

### glab api

| flag | 含义 |
|------|------|
| `--hostname` 或 `-h` | 指定 host，跨实例不用切默认 |
| `--paginate` | 自动跟 Link header 翻所有页 |
| `-X <METHOD>` | 指定 HTTP 方法（默认 GET） |
| `-f key=value` | 字符串字段 |
| `-F key=value` | 带类型转换的字段（数字、布尔） |

### glab auth

| flag | 含义 |
|------|------|
| `--hostname <host>` | 指定 host（auth login / status） |
| `--stdin --token` | stdin 传 token（auth login，非交互） |

### glab config

| flag | 含义 |
|------|------|
| `-h <host>` | 指定 host 级配置（config set / get） |
| `host`、`api_protocol`、`git_protocol`、`skip_tls_verify` | 常用配置项 |

## ❌ 看起来像但不存在的 flag

下面这些是 LLM 常编造的 flag。怀疑时记得查或验证：

| 看似存在 | 实际 | 备注 |
|---------|------|------|
| `glab ci get --pipeline-id <id>` | `glab ci get --pipeline <id>` | 是 `--pipeline`，不带 `-id` 后缀 |
| `glab ci trace --job <id>` | `glab ci trace <id>` | job-id 是位置参数 |
| `glab mr list --all` | 不存在 | 想跨项目用 `glab api`，不要 `--all` |
| `glab mr merge --yes` | 多数版本不需要 | merge 默认不再二次确认 |
| `glab config set -g <key>` | `glab config set <key>` 或 `-h <host> <key>` | 没有 `-g`（global） |
| `glab auth login --token <token>` | `glab auth login --stdin --token` 配 stdin | token 必须 stdin 传，不能直接 flag 传明文 |
| `GLAB_CA_CERT` 环境变量 | 不存在 | 装系统根证书或 `skip_tls_verify true` |
| `glab mr list --reviewer-username` | `glab mr list --reviewer @me` | 用 `@me` 或 `--reviewer <user>` |

## 验证方法

任何 flag 不确定时，最快的验证方式：

```powershell
glab <command> <subcommand> --help
```

输出会列出所有真实存在的 flag。比记忆/猜测靠谱。

例：

```powershell
glab mr create --help
glab ci trace --help
glab api --help
```

## 升级 glab 后验证

新版本会加 flag、改默认行为。怀疑某个 flag 是否在当前版本可用：

```powershell
glab --version
glab check-update
```

老版本不支持的 flag，报错信息一般是 `Error: unknown flag: --xxx`。
