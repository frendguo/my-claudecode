# glab api + jq 高级用法

封装命令没覆盖到的所有 GitLab 操作都能走 `glab api` 直打，自动带认证。配合 `jq` 做后处理，能搞定批量、跨项目、自定义字段提取这些场景。

## glab api 基础

```powershell
# GET 任意 REST 端点
glab api "/version"
glab api "/user"
glab api "/merge_requests?state=opened&per_page=100"

# 项目级端点（用 :id 占位，-F id 传 project ID）
glab api "projects/:id/protected_branches" -F id=12345

# group 级端点（:id 接受 URL-encoded 路径，platform 直接写，platform/sub 要写 platform%2Fsub）
glab api "/groups/platform/merge_requests?scope=created_by_me&state=opened"
glab api "/groups/platform%2Fbackend/projects?include_subgroups=true"

# POST：-f 传字符串字段，-F 传带类型转换的字段（数字、布尔等）
glab api "projects/:id/merge_requests/123/notes" -F id=12345 -f body="comment"
glab api "projects/:id/merge_requests" -F id=12345 -f source_branch=feat -f target_branch=main -f title="..."

# 自定义 HTTP 方法
glab api -X DELETE "projects/:id/merge_requests/123" -F id=12345
glab api -X PUT "projects/:id" -F id=12345 -f description="..."
```

## --hostname：跨实例直接调用

不需要切默认 host 也不需要进 git 仓库目录，直接对指定 host 发请求：

```powershell
glab api --hostname git.acme-corp.local "/version"
glab api --hostname gitlab.com "/user"
```

这是脚本场景的最佳实践：一份脚本同时操作多个 GitLab 实例，不用反复 `$env:GITLAB_HOST` 切来切去。短写 `-h`：

```powershell
glab api -h git.acme-corp.local "projects/:id/merge_requests" -F id=42
```

## --paginate：自动分页

GitLab API 单页最多 100 条，大列表必须分页。`--paginate` 自动跟 `Link: rel="next"` 翻完所有页，把多页拼成一个大 JSON 数组：

```powershell
glab api --paginate "/merge_requests?state=opened&per_page=100"
glab api --paginate "/groups/platform/projects?include_subgroups=true&per_page=100"
```

不加 `--paginate` 时只返回第一页。配合 `per_page=100` 减少请求次数。

## scope 参数（避免查 user id）

GitLab API 的 `scope` 参数是个糖，不用先查自己的 user id：

```
scope=created_by_me   等价于"我作为 author"
scope=assigned_to_me  等价于"指派给我"
```

```powershell
glab api --paginate "/merge_requests?scope=created_by_me&state=opened&per_page=100"
glab api --paginate "/issues?scope=assigned_to_me&state=opened"
```

## jq 后处理

`glab api` 默认输出 JSON，配 `jq` 做提取/筛选/格式化。Windows 装 jq：`winget install jqlang.jq`。

### 基础提取

```powershell
# 提取字段子集
glab api "/merge_requests?state=opened&per_page=100" `
  | jq '[.[] | {iid, title, web_url}]'

# 只要 ID 列表（每行一个）
glab api "/merge_requests?state=opened" | jq -r '.[].iid'

# 提取嵌套字段
glab api "/merge_requests?state=opened" `
  | jq '[.[] | {iid, author: .author.username, web_url}]'
```

### 输出 CSV / TSV（贴 Excel 神器）

```powershell
# CSV（IID, URL 两列）
glab api --paginate "/merge_requests?scope=created_by_me&state=opened&per_page=100" `
  | jq -r '.[] | [.iid, .web_url] | @csv' > my-mrs.csv

# TSV（项目路径 + IID + URL）
glab api --paginate "/groups/platform/merge_requests?scope=created_by_me&state=opened" `
  | jq -r '.[] | [.references.full, .iid, .web_url] | @tsv' > my-mrs.tsv
```

`references.full` 是个好用的字段：返回类似 `platform/backend/api!42` 的完整定位字符串，比单独的 IID 更直观。

### jq -s 'add'：合并多次响应

`--paginate` 已经能处理单端点的多页。但如果要先列项目、再对每个项目调 MR 列表（两次嵌套调用），需要把多次响应合并：

```powershell
$mrs = glab api --paginate "/groups/platform/projects?include_subgroups=true&per_page=100" `
  | jq -r '.[].id' `
  | ForEach-Object {
      glab api --paginate "projects/$_/merge_requests?state=opened&per_page=100"
    }
$mrs | jq -s 'add | [.[] | {iid, web_url}]'
```

`jq -s` 把多个 JSON 数组当 stdin 输入，每个数组作为顶层数组的一个元素；`add` 把它们拼成一个扁平数组。

注意：用 group 级端点 `/groups/:id/merge_requests` 一次就能查整个 group，**优先用它**，不要先列项目再循环查。

### select 过滤

```powershell
# 标题含某关键字
glab api "/merge_requests?state=opened" | jq '[.[] | select(.title | contains("auth"))]'

# 按 web_url 过滤
glab api "/merge_requests?scope=created_by_me" `
  | jq '[.[] | select(.web_url | contains("/platform/")) | {iid, web_url}]'

# 多条件
glab api "/merge_requests?state=opened" `
  | jq '[.[] | select(.draft == false and .upvotes > 1)]'
```

## ConvertFrom-Json 备选（不装 jq）

PowerShell 原生支持 JSON：

```powershell
$mrs = glab api --paginate "/merge_requests?state=opened&per_page=100" | ConvertFrom-Json
$mrs | Select-Object iid, title, web_url
$mrs | Where-Object { $_.title -match "auth" } | Select-Object iid, web_url

# 导出 CSV
$mrs | Select-Object iid, web_url | Export-Csv -Path my-mrs.csv -NoTypeInformation -Encoding utf8
```

适合临时一次性查询。复杂转换还是 jq 更灵活。

## 实战配方

### 我作为 author 的 open MR（跨整个 group）

```powershell
glab api --hostname git.acme-corp.local --paginate `
  "/groups/platform/merge_requests?scope=created_by_me&state=opened&per_page=100" `
  | jq -r '.[] | [.references.full, .iid, .web_url] | @tsv'
```

### 给某 group 下所有项目的最新 MR 加 label

```powershell
$mrs = glab api --paginate "/groups/platform/merge_requests?state=opened&per_page=100" `
  | ConvertFrom-Json
foreach ($mr in $mrs) {
  glab api -X PUT "projects/$($mr.project_id)/merge_requests/$($mr.iid)" `
    -f "add_labels=release-2026"
}
```

### 把所有失败 pipeline 的 trace 拉下来

```powershell
glab api --paginate "projects/:id/pipelines?status=failed&per_page=100" -F id=12345 `
  | jq -r '.[].id' `
  | ForEach-Object {
      glab api "projects/:id/pipelines/$_/jobs" -F id=12345 `
        | jq -r '.[] | select(.status == "failed") | .id' `
        | ForEach-Object {
            glab ci trace $_ > "fail-$_.log"
          }
    }
```

## REST API 文档

完整端点列表：https://docs.gitlab.com/ee/api/

不知道某个能力对应哪个端点时，先 `glab <command> --help` 看 glab 是否封装；没有再去 API 文档搜。
