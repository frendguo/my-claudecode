# 自托管 GitLab 配置

国内/企业环境下自托管 GitLab 居多，下面是踩坑后的关键事实。

## 多实例认证

`glab` 支持同时认证多个 GitLab 主机，每个主机的 token 独立存储在 `~/.config/glab-cli/config.yml`（Windows 是 `%USERPROFILE%\.config\glab-cli\config.yml`）。登录方式：

```powershell
# 登录到自托管实例（交互式，按提示粘贴 Personal Access Token）
glab auth login --hostname gitlab.example.com

# 非交互式（CI/脚本里用，stdin 传 token）
"glpat-xxxxxxxxxxx" | glab auth login --hostname gitlab.example.com --stdin --token
```

Token 来源：自托管 GitLab → User Settings → Access Tokens，勾选 `api`、`read_repository`、`write_repository` scope。

## 默认主机切换

同时登录了多个主机时，`glab` 用 "default host" 决定默认操作哪个。三种切换办法，优先级从高到低：

```powershell
# 方法 1：单条命令临时指定（高频推荐）
$env:GITLAB_HOST="gitlab.example.com"; glab mr list

# 方法 2：通过 -R 指定完整 URL，自动推断主机
glab mr list -R "https://gitlab.example.com/group/project"

# 方法 3：永久切默认
glab config set host gitlab.example.com
```

判断当前默认主机：`glab config get host`。

进到具体仓库目录后，glab 会从 `git remote` 自动识别 host，不需要手动切：

```powershell
cd k8s-cluster      # remote 指向 git.acme-corp.local
glab mr list        # 自动打到 git.acme-corp.local
```

## 自签 / 私有 CA 证书

企业内网常见，glab 默认会校验证书。两种处理：

```powershell
# 临时跳过校验（仅排查用，不要长期开）
glab config set -h gitlab.example.com skip_tls_verify true
```

```powershell
# 推荐：把企业根证书加进系统受信根，glab 会自动信任
Import-Certificate -FilePath "C:\path\to\company-root-ca.crt" `
  -CertStoreLocation Cert:\LocalMachine\Root
# 或图形界面：certmgr.msc → 受信任的根证书颁发机构 → 导入
```

装好后 glab、git、curl 都会自动信任，无需额外配置。

## HTTP vs HTTPS

自建实例如果只开 HTTP（不推荐但常见），需要显式声明协议：

```powershell
glab config set -h gitlab.example.com api_protocol http
glab config set -h gitlab.example.com git_protocol http
```

否则 `glab` 默认走 https，所有请求都会失败（典型表现：connection refused / EOF）。

## 仓库 URL 格式差异

自托管 GitLab 经常使用多级 group（`group/sub-group/project`），`-R` 参数要写完整路径：

```powershell
# 正确
glab mr list -R platform/infra/k8s-cluster

# 错误（缺少中间层）
glab mr list -R platform/k8s-cluster   # 404
```

SSH 克隆时也要注意，自托管常见 22 以外端口：

```
ssh://git@gitlab.example.com:2222/group/project.git
```

## 完整双实例配置示例

公司内部 `git.acme-corp.local`（HTTP + 自签）+ 公网 `gitlab.com`：

```powershell
# 1. 公网 GitLab（最简单，先搞定）
glab auth login --hostname gitlab.com

# 2. 内部 GitLab：先声明协议，再登录
glab config set -h git.acme-corp.local api_protocol http
glab config set -h git.acme-corp.local git_protocol http
glab auth login --hostname git.acme-corp.local

# 3. 设默认 host（哪个用得多设哪个）
glab config set host git.acme-corp.local

# 4. 验证
glab auth status
```

## PowerShell 小工具：会话内一键切

把这两个函数丢进 `$PROFILE`：

```powershell
function glab-acme { $env:GITLAB_HOST = "git.acme-corp.local" }
function glab-com  { $env:GITLAB_HOST = "gitlab.com" }
```

之后终端敲 `glab-acme` 切到内网，`glab-com` 切到公网。

## 配置文件直接编辑

某个 host 配错了想推倒重来，直接编辑 `%USERPROFILE%\.config\glab-cli\config.yml` 删掉对应 host 段，再 `glab auth login` 重登。结构：

```yaml
git_protocol: http
host: git.acme-corp.local
hosts:
  git.acme-corp.local:
    token: glpat-xxxxxxxxxxx
    api_protocol: http
    api_host: git.acme-corp.local
    git_protocol: http
  gitlab.com:
    token: glpat-yyyyyyyyyyy
    api_protocol: https
    api_host: gitlab.com
```

## 自托管常见坑

1. **`connection refused` / `EOF`**：API 走了 https 但实例只开 HTTP。`glab config set -h <host> api_protocol http`。
2. **`tls: failed to verify certificate`**：自签根证书没导入。装系统根证书池，或临时 `skip_tls_verify true`。
3. **`unknown host` / 401**：默认 host 切错了。`glab config get host` 检查，或 `$env:GITLAB_HOST` 临时覆盖。
4. **`-R` 路径 404**：自托管多级 group 必须写全 `group/sub/project`。
5. **PAT 过期**：`glab auth status` 会显示 token 是否有效；过期重新 `glab auth login --hostname <host>`。
6. **git push 弹密码框**：glab 的认证只管 API；git 推送凭证另存。第一次 push 弹密码框时填用户名 + PAT，勾保存即可。
