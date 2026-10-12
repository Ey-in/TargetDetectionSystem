<#
.SYNOPSIS
    生成贡献统计与版本控制日志（课程要求的工作量证明）

.DESCRIPTION
    课程第 3 页明确要求提交「代码开发过程中的关键记录（如版本控制日志、调试记录、
    测试用例设计）」。本脚本负责其中的版本控制日志部分。

    统计口径说明：本项目采用 Squash 合并，main 上每个非初始提交对应一个 PR，
    因此「提交数」约等于「PR 数」。

.PARAMETER Since
    起始日期，如 2026-10-12

.PARAMETER Until
    截止日期

.PARAMETER Author
    只统计某个人（按作者名匹配）

.PARAMETER OutFile
    同时输出一份 Markdown 表格到指定文件，可直接贴进实验报告

.PARAMETER ExportLog
    导出完整版本控制日志到指定文件，作为报告附录

.EXAMPLE
    .\scripts\worklog.ps1

.EXAMPLE
    .\scripts\worklog.ps1 -OutFile docs\贡献统计.md

.EXAMPLE
    .\scripts\worklog.ps1 -ExportLog 提交物\版本控制日志.txt
#>
[CmdletBinding()]
param(
    [string]$Since = "",
    [string]$Until = "",
    [string]$Author = "",
    [string]$OutFile = "",
    [string]$ExportLog = ""
)

$ErrorActionPreference = "Stop"
# PS 5.1 控制台默认 GBK，git 的 UTF-8 输出会乱码
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Write-Step { param($m) Write-Host ""; Write-Host "=== $m ===" -ForegroundColor Cyan }
function Write-Note { param($m) Write-Host "  $m" -ForegroundColor Gray }
function Write-Warn { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# ---------------------------------------------------------------- 读取日志
$gitArgs = @(
    "log", "--no-merges", "--date=short",
    "--pretty=format:@@@%H|%an|%ae|%ad|%s",
    "--numstat"
)
if ($Since)  { $gitArgs += "--since=$Since" }
if ($Until)  { $gitArgs += "--until=$Until" }
if ($Author) { $gitArgs += "--author=$Author" }

$raw = & git @gitArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "读取 git 日志失败。请确认当前目录是 git 仓库。" -ForegroundColor Red
    exit 1
}

$commits = New-Object System.Collections.ArrayList
$cur = $null

foreach ($line in $raw) {
    if ($line.StartsWith("@@@")) {
        $p = $line.Substring(3) -split '\|', 5
        $cur = [PSCustomObject]@{
            Hash    = $p[0]
            Author  = $p[1]
            Email   = $p[2]
            Date    = $p[3]
            Subject = $p[4]
            Added   = 0
            Deleted = 0
            Files   = 0
            Paths   = New-Object System.Collections.ArrayList
        }
        [void]$commits.Add($cur)
    }
    elseif ($cur -and $line -match '^(\d+|-)\t(\d+|-)\t(.+)$') {
        if ($matches[1] -ne '-') { $cur.Added   = $cur.Added   + [int]$matches[1] }
        if ($matches[2] -ne '-') { $cur.Deleted = $cur.Deleted + [int]$matches[2] }
        $cur.Files = $cur.Files + 1
        [void]$cur.Paths.Add($matches[3])
    }
}

if ($commits.Count -eq 0) {
    Write-Host "指定范围内没有提交记录。" -ForegroundColor Yellow
    exit 0
}

$validTypes = @('feat','fix','docs','test','chore','refactor','perf','style','build','ci','revert')

# ---------------------------------------------------------------- 总览
Write-Step "总览"

# 注意：必须用 @() 强制成数组。只有一个唯一日期时 Select-Object -Unique 返回的是
# 字符串而非数组，此时 $allDates[0] 会取到首字符（"2026-10-12"[0] == '2'）
$allDates = @($commits | Select-Object -ExpandProperty Date -Unique | Sort-Object)
Write-Note "提交总数：$($commits.Count)"
Write-Note "时间跨度：$($allDates[0]) ~ $($allDates[-1])"
Write-Note "活跃天数：$($allDates.Count)"

# ---------------------------------------------------------------- 按人
Write-Step "按人统计"

$byAuthor = $commits | Group-Object -Property Author | ForEach-Object {
    $g = $_.Group
    $dates = @($g | Select-Object -ExpandProperty Date -Unique)
    [PSCustomObject]@{
        '姓名'     = $_.Name
        '邮箱'     = ($g | Select-Object -First 1).Email
        '提交数'   = $g.Count
        '新增行'   = ($g | Measure-Object -Property Added   -Sum).Sum
        '删除行'   = ($g | Measure-Object -Property Deleted -Sum).Sum
        '涉及文件' = ($g | Measure-Object -Property Files   -Sum).Sum
        '活跃天数' = $dates.Count
        '首次提交' = ($g | Sort-Object Date | Select-Object -First 1).Date
        '末次提交' = ($g | Sort-Object Date | Select-Object -Last  1).Date
    }
} | Sort-Object '提交数' -Descending

$byAuthor | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

# ---------------------------------------------------------------- 按人 × 模块
Write-Step "按人 × 模块（体现分工与产出物）"

$authorModule = $commits | ForEach-Object {
    $a = $_.Author
    foreach ($p in $_.Paths) {
        $norm = $p -replace '\\', '/'
        $seg = $norm.Split('/')
        $top = $seg[0]
        [PSCustomObject]@{ 作者 = $a; 模块 = $top }
    }
} | Group-Object -Property 作者, 模块 | ForEach-Object {
    $parts = $_.Name -split ', '
    [PSCustomObject]@{
        '姓名'   = $parts[0]
        '模块'   = $parts[1]
        '改动数' = $_.Count
    }
} | Sort-Object '姓名', '改动数' -Descending

$authorModule | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

# ---------------------------------------------------------------- 按类型
Write-Step "提交类型分布"

$byType = $commits | ForEach-Object {
    $t = '(未规范)'
    if ($_.Subject -match '^([a-z]+)') {
        if ($validTypes -contains $matches[1]) { $t = $matches[1] }
    }
    $t
} | Group-Object | Sort-Object Count -Descending | ForEach-Object {
    [PSCustomObject]@{ '类型' = $_.Name; '数量' = $_.Count }
}

$byType | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

$unregulated = ($byType | Where-Object { $_.'类型' -eq '(未规范)' } | Select-Object -First 1)
if ($unregulated) {
    Write-Warn "有 $($unregulated.'数量') 条提交信息不符合 Conventional Commits 规范"
}

# ---------------------------------------------------------------- 周活跃度
Write-Step "周活跃度"

$byWeek = $commits | Group-Object -Property {
    $d = [datetime]::ParseExact($_.Date, 'yyyy-MM-dd', $null)
    $monday = $d.AddDays(-(([int]$d.DayOfWeek + 6) % 7))
    $monday.ToString('yyyy-MM-dd')
} | Sort-Object Name | ForEach-Object {
    [PSCustomObject]@{
        '周起始(周一)' = $_.Name
        '提交数'       = $_.Count
        '参与人数'     = ($_.Group | Select-Object -ExpandProperty Author -Unique).Count
    }
}

$byWeek | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

# ---------------------------------------------------------------- 风险提示
Write-Step "风险提示"

$authorCount = ($commits | Select-Object -ExpandProperty Author -Unique).Count
if ($authorCount -eq 1 -and $commits.Count -gt 5) {
    Write-Warn "全部 $($commits.Count) 条提交都来自同一个人：$($byAuthor[0].'姓名')"
    Write-Warn "这会让「工作量证明」无法体现分工。请确认："
    Write-Warn "  1. 每位组员是否都已配置自己的 git user.name / user.email"
    Write-Warn "  2. 代码是否都由自己提交（而不是一人代提交全部）"
}

$noEmail = $commits | Where-Object { -not $_.Email } | Select-Object -First 1
if ($noEmail) { Write-Warn "存在没有邮箱的提交，无法归属到 GitHub 账号" }

# ---------------------------------------------------------------- 导出
if ($OutFile) {
    $md = New-Object System.Collections.ArrayList
    [void]$md.Add("# 贡献统计")
    [void]$md.Add("")
    [void]$md.Add("> 由 ``scripts/worklog.ps1`` 生成，统计范围：$($allDates[0]) ~ $($allDates[-1])")
    [void]$md.Add(">")
    [void]$md.Add("> 本项目采用 Squash 合并，main 上每个非初始提交对应一个 PR，故「提交数」约等于「PR 数」。")
    [void]$md.Add("")
    [void]$md.Add("## 总体情况")
    [void]$md.Add("")
    [void]$md.Add("| 指标 | 数值 |")
    [void]$md.Add("|---|---|")
    [void]$md.Add("| 提交总数 | $($commits.Count) |")
    [void]$md.Add("| 参与人数 | $authorCount |")
    [void]$md.Add("| 时间跨度 | $($allDates[0]) ~ $($allDates[-1]) |")
    [void]$md.Add("| 活跃天数 | $($allDates.Count) |")
    [void]$md.Add("")
    [void]$md.Add("## 按成员统计")
    [void]$md.Add("")
    [void]$md.Add("| 姓名 | 邮箱 | 提交数 | 新增行 | 删除行 | 涉及文件 | 活跃天数 | 首次提交 | 末次提交 |")
    [void]$md.Add("|---|---|---|---|---|---|---|---|---|")
    foreach ($r in $byAuthor) {
        [void]$md.Add("| $($r.'姓名') | $($r.'邮箱') | $($r.'提交数') | $($r.'新增行') | $($r.'删除行') | $($r.'涉及文件') | $($r.'活跃天数') | $($r.'首次提交') | $($r.'末次提交') |")
    }
    [void]$md.Add("")
    [void]$md.Add("## 成员与模块分工")
    [void]$md.Add("")
    [void]$md.Add("| 姓名 | 模块 | 改动次数 |")
    [void]$md.Add("|---|---|---|")
    foreach ($r in $authorModule) {
        [void]$md.Add("| $($r.'姓名') | $($r.'模块') | $($r.'改动数') |")
    }
    [void]$md.Add("")
    [void]$md.Add("## 提交类型分布")
    [void]$md.Add("")
    [void]$md.Add("| 类型 | 数量 |")
    [void]$md.Add("|---|---|")
    foreach ($r in $byType) {
        [void]$md.Add("| $($r.'类型') | $($r.'数量') |")
    }
    [void]$md.Add("")
    [void]$md.Add("## 周活跃度")
    [void]$md.Add("")
    [void]$md.Add("| 周起始（周一） | 提交数 | 参与人数 |")
    [void]$md.Add("|---|---|---|")
    foreach ($r in $byWeek) {
        [void]$md.Add("| $($r.'周起始(周一)') | $($r.'提交数') | $($r.'参与人数') |")
    }
    [void]$md.Add("")

    $outPath = Join-Path $repoRoot $OutFile
    $outDir = Split-Path -Parent $outPath
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    $md -join "`r`n" | Out-File -FilePath $outPath -Encoding utf8
    Write-Host ""
    Write-Host "  已导出 Markdown：$outPath" -ForegroundColor Green
}

if ($ExportLog) {
    $logPath = Join-Path $repoRoot $ExportLog
    $logDir = Split-Path -Parent $logPath
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    # 完整日志（含每个提交改了哪些文件），这是最有说服力的版本控制日志
    & git log --no-merges --date=short --pretty=format:"commit %h%n日期: %ad%n作者: %an <%ae>%n%n    %s%n" --stat |
        Out-File -FilePath $logPath -Encoding utf8
    Write-Host "  已导出版本控制日志：$logPath" -ForegroundColor Green
}

Write-Host ""
