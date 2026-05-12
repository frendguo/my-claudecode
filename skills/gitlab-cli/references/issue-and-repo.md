# Issue 和 Repo 操作

## Issue

```powershell
# 列表
glab issue list                          # 当前仓库的 open issue
glab issue list --assignee @me           # 指派给我的
glab issue list --author @me             # 我创建的
glab issue list --label "bug" --state opened
glab issue list --milestone "v2.0"
glab issue list --search "login"

# 查看
glab issue view 42
glab issue view 42 --comments            # 带评论
glab issue view 42 --web                 # 浏览器打开

# 创建
glab issue create --title "..." --description "..." --label bug --assignee @me
glab issue create                        # 交互式，会一步步问

# 评论与更新
glab issue note 42 -m "已经在 !123 修复"
glab issue update 42 --label "wontfix"
glab issue update 42 --unlabel "wip" --milestone "v2.0"

# 状态
glab issue close 42
glab issue reopen 42
glab issue subscribe 42 / unsubscribe 42

# Issue Board
glab issue board view                    # 看看板
```

## Repo

```powershell
# 克隆——自动用已配置的默认 host，不用手写 URL
glab repo clone group/sub/project
glab repo clone -g some-group            # 克隆整个 group 下所有项目

# 查看
glab repo view                           # 当前仓库概览
glab repo view group/project             # 别的仓库
glab repo view --web                     # 浏览器打开仓库主页

# 创建
glab repo create new-project --group some-group --private
glab repo create new-project --public --description "..."

# Fork
glab repo fork group/project --clone     # fork 后立刻 clone

# 搜索
glab repo search --search "keyword"
glab repo list --group some-group        # 列 group 下的所有项目

# 成员管理
glab repo members list
glab repo members add @username --access-level developer

# 镜像
glab repo mirror group/project --pull --url "https://github.com/foo/bar"

# 转移与删除（危险，少用）
glab repo transfer old-project --namespace new-group
glab repo delete old-project             # 会要求二次确认
```

`glab repo clone` 比 `git clone` 好的地方：自动按你已配置的 host + token 处理认证，从自托管克隆时不用手写 https URL，也不会遇到鉴权问题。

## Snippet（少用但有时方便）

```powershell
glab snippet create --title "..." --filename foo.py --content "..."
glab snippet view 12345
glab snippet list
```

## Release

```powershell
glab release list
glab release view v1.2.3
glab release create v1.2.3 --notes "..." --assets ./dist/*.tar.gz
glab release delete v0.0.1
```

## Variable（CI/CD 变量管理）

```powershell
glab variable list                       # 当前项目的 CI 变量
glab variable list --group some-group    # group 级变量
glab variable set DATABASE_URL "postgres://..." --protected --masked
glab variable get DATABASE_URL
glab variable delete DATABASE_URL
```

## Schedule（定时任务）

```powershell
glab schedule list
glab schedule create --description "nightly" --ref main --cron "0 2 * * *"
glab schedule run <ID>                   # 手动触发一次
```
