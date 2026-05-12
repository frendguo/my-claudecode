# CI/CD 流水线完整命令参考

## 看状态

```powershell
glab ci status                            # 当前分支最新 pipeline，实时刷新
glab ci status --branch develop           # 指定分支
glab ci list                              # 历史 pipeline 列表
glab ci list --status failed --per-page 10 # 只看失败的
glab ci list --branch feat/x --per-page 5 # 指定分支历史
glab ci get --pipeline <PIPELINE_ID>      # 看某条 pipeline 完整 JSON
```

注意：`glab ci get` 用 `--pipeline` 不是 `--pipeline-id`（容易记错）。

## 看日志

CI 红了找原因的核心命令：

```powershell
glab ci trace                             # 当前分支最新 pipeline，交互选 job
glab ci trace 123456                      # 指定 job ID 直接拉日志（位置参数，不是 --job）

# 日志太长想存下来
glab ci trace 123456 | Out-File -Encoding utf8 .\ci-failure.log
```

`glab ci trace` 底层是 SSE 流，VPN/代理不稳会断开。断了改用 `glab ci status` 轮询更稳。

## 触发与重试

```powershell
glab ci run                               # 当前分支跑一次新 pipeline
glab ci run --branch feature-x            # 指定分支
glab ci run --variables KEY:value,KEY2:value2 # 传变量

glab ci retry 123456                      # 重试某个失败 job
glab ci cancel 78901                      # 取消运行中
glab ci delete 123                        # 删除 pipeline 记录
```

整条 pipeline 重跑（不是只重试单个 job）用 `glab ci run --branch <分支>`。

## 校验 .gitlab-ci.yml

```powershell
glab ci lint                              # 校验当前 .gitlab-ci.yml
glab ci lint --path .gitlab-ci.staging.yml # 指定路径
glab ci config                            # 看 include/extends/anchors 展开后的最终 yaml
```

`glab ci lint` 把 yml 发到 GitLab 服务端用真实解析器校验，比本地 yaml 语法检查靠谱（能识别 `include`、`extends`、`rules` 这些 GitLab 专属语义）。

如果 `lint` 通过但 pipeline 还是炸，说明不是 yml 语法问题，而是 job 内脚本逻辑/镜像/变量问题，回到 `glab ci trace` 看日志。

## Artifact 下载

```powershell
glab ci artifact main build-job            # 下载分支 + job 名对应的 artifact
glab ci artifact <ref> <jobName>           # 通用形式
```

下载的是该 ref 上最新一次成功 pipeline 的 artifact，不是任意 pipeline 的。

## 触发器（外部触发 pipeline）

```powershell
glab ci run-trig --token <trigger-token> --variables KEY:value
glab ci trigger <job-id>                  # 触发某个 manual job
```

## TUI 模式

```powershell
glab ci view                              # 交互式 TUI，方向键选 job，Enter 看详情
```

`view` 适合人在终端看，能看到整个 pipeline 的 job 树形结构。脚本里别用，用 `status` / `list`。

## 5 步 CI 排错工作流模板

```powershell
glab ci status                                    # 1. 整体状态
glab ci status --branch feat/x                    # 2. 找失败 job（输出会列所有 job 状态）
glab ci trace                                     # 3. 交互选失败 job 看日志
glab ci retry <JOB_ID>                            # 4. 网络抖动重试
glab ci lint                                      # 5. yml 改了先 lint 再 push
```
