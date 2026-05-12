# MR 合并请求完整命令参考

## 创建

```powershell
# 标准——用最近一次 commit 自动填标题/正文
glab mr create --fill

# 草稿
glab mr create --fill --draft

# 指定标签和指派
glab mr create --fill --label "bugfix,backend" --assignee @me

# 自定义目标分支
glab mr create --target-branch develop --title "feat: x" --description "..."

# 创建后立刻打开浏览器
glab mr create --fill --web
```

`--fill` 是高频参数：自动用最近 commit 的 subject 作标题、body 作描述，省去交互。

## 列表查询

```powershell
glab mr list                              # 当前仓库的 open MR
glab mr list --assignee @me               # 指派给我的
glab mr list --reviewer @me               # 让我评审的
glab mr list --author @me                 # 我创建的
glab mr list --state merged --per-page 20 # 已合并的（最近 20）
glab mr list --state closed               # 已关闭未合并
glab mr list --search "auth"              # 标题/正文匹配
glab mr list --label "bug" --label "p0"   # 多标签筛选
glab mr list --output json                # JSON 输出，给后续脚本用
```

跨项目查询（不是当前仓库）走 `glab api`，见 `references/api-and-jq.md`。

## 查看

```powershell
glab mr view 123                          # 终端展示标题/描述/状态/CI
glab mr view 123 --comments               # 带所有评论
glab mr view 123 --web                    # 在浏览器打开（路过看一眼）
glab mr diff 123                          # 看代码改动
glab mr diff 123 | Out-Host -Paging       # 分页阅读大 diff（PowerShell）
```

## 检出到本地

```powershell
glab mr checkout 123                      # 拉源分支并切过去
glab mr checkout feat/payment-refactor    # 用源分支名也行
glab mr checkout 123 -b review/123        # 指定本地分支名
```

`checkout` 会自动 fetch + 切分支，跑完测试后 `git checkout -` 切回原分支。

## 评论与互动

```powershell
glab mr note 123 -m "LGTM"                # 加评论
glab mr note 123 -m "建议把 magic number 提取成常量"

glab mr update 123 --label "needs-rebase"
glab mr update 123 --unlabel "wip"
glab mr update 123 --milestone "v2.0"
glab mr update 123 --assignee @username

glab mr subscribe 123                     # 订阅更新通知
glab mr todo 123                          # 加到自己的 to-do
```

## 审批

```powershell
glab mr approve 123
glab mr approvers 123                     # 看谁是合格审批人
glab mr revoke 123                        # 撤回审批
```

## 合并

```powershell
glab mr merge 123                         # 按仓库默认策略合并
glab mr merge 123 --squash --remove-source-branch  # 最常用：squash 后删源分支
glab mr merge 123 --rebase                # rebase 合并
glab mr merge 123 --squash --squash-message "feat: 自定义合并消息"
glab mr merge 123 --when-pipeline-succeeds # 等 CI 通过自动合（推荐）
```

`--when-pipeline-succeeds` 是好东西：MR 已批准但 CI 还在跑时，敲完命令就可以走人，CI 过了 GitLab 自动合并。

## 同步与冲突

```powershell
glab mr rebase 123                        # 触发服务端 rebase 到目标分支
```

冲突解决还是要本地 `git checkout` + `git rebase` 手动来，`glab mr rebase` 只能处理无冲突的情况。

## 关闭与重开

```powershell
glab mr close 123
glab mr reopen 123
glab mr delete 123                        # 永久删除（少用）
```

## 5 步评审工作流模板

```powershell
glab mr list --reviewer @me               # 1. 看待办
glab mr checkout 456                      # 2. 拉到本地
glab mr diff 456                          # 3. 看 diff
glab mr view 456 --comments               # （或看上下文评论）
glab mr note 456 -m "LGTM, 建议把 magic number 提取成常量"  # 4. 评论
glab mr approve 456                       # 5a. 批准
glab mr merge 456 --squash --remove-source-branch  # 5b. 合并
```
