<#
.SYNOPSIS
    把 docs/ 下的 Markdown 文档导出为 Word，供提交

.DESCRIPTION
    工作稿永远只有一份 —— docs/ 下的 Markdown。
    提交物/ 里的文件是导出生成的产物，不要手工编辑，否则两份会逐渐分叉，
    而"仓库里的记录"正是我们的工作量证明。

    需要 pandoc：winget install --id JohnMacFarlane.Pandoc

.PARAMETER Files
    要导出的文件（相对仓库根目录）。不指定则导出四份课程文档。

.PARAMETER OutDir
    输出目录，默认「提交物」

.PARAMETER Pdf
    同时尝试导出 PDF。需要本机装有 LaTeX（一般没装），失败时脚本会提示改用
    Word 另存为 PDF —— 对课程提交来说这一步更省事。

.EXAMPLE
    .\scripts\export_docs.ps1

.EXAMPLE
    .\scripts\export_docs.ps1 -Files docs\01-需求规格说明书.md
#>
[CmdletBinding()]
param(
    [string[]]$Files = @(),
    [string]$OutDir = "提交物",
    [switch]$Pdf
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Write-Note { param($m) Write-Host "  $m" -ForegroundColor Gray }

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# ---------------------------------------------------------------- 默认文件
if ($Files.Count -eq 0) {
    $Files = @(
        "docs\01-需求规格说明书.md",
        "docs\02-概要设计说明书.md",
        "docs\03-详细设计说明书.md",
        "docs\04-测试报告.md"
    )
}

# ---------------------------------------------------------------- 检查 pandoc
$pandoc = Get-Command pandoc -ErrorAction SilentlyContinue
if (-not $pandoc) {
    Write-Host ""
    Write-Host "未找到 pandoc。" -ForegroundColor Red
    Write-Host ""
    Write-Note "pandoc 用于把 Markdown 转成 Word，安装命令："
    Write-Host "    winget install --id JohnMacFarlane.Pandoc" -ForegroundColor Yellow
    Write-Host ""
    Write-Note "装完重开终端再运行本脚本。"
    Write-Note "（若暂时不想装，也可以手工把 Markdown 内容复制进 Word —— 只是费时且易出错。）"
    Write-Host ""
    exit 1
}
Write-Host ""
Write-Note "pandoc：$($pandoc.Source)"

# ---------------------------------------------------------------- 输出目录
$outFull = Join-Path $repoRoot $OutDir
if (-not (Test-Path $outFull)) {
    New-Item -ItemType Directory -Path $outFull -Force | Out-Null
    Write-Note "已创建输出目录：$outFull"
}

# ---------------------------------------------------------------- 转换
$okCount = 0
$failCount = 0

foreach ($rel in $Files) {
    $src = Join-Path $repoRoot $rel
    if (-not (Test-Path $src)) {
        Write-Host "  跳过（文件不存在）：$rel" -ForegroundColor Yellow
        $failCount++
        continue
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($src)
    $dst = Join-Path $outFull "$baseName.docx"

    Write-Note "转换 $rel …"
    # -f gfm: 按 GitHub 风格解析，表格与任务列表才能正确转换
    & pandoc $src -f gfm -t docx -o $dst --toc --toc-depth=3

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] $baseName.docx" -ForegroundColor Green
        $okCount++
    } else {
        Write-Host "  [XX] $rel 转换失败" -ForegroundColor Red
        $failCount++
    }
}

# ---------------------------------------------------------------- PDF
if ($Pdf) {
    $latex = Get-Command xelatex -ErrorAction SilentlyContinue
    if (-not $latex) {
        $latex = Get-Command pdflatex -ErrorAction SilentlyContinue
    }
    if (-not $latex) {
        Write-Host ""
        Write-Host "  未找到 LaTeX 引擎，跳过 PDF 导出。" -ForegroundColor Yellow
        Write-Note "课程提交用 Word 就够了。若确实需要 PDF："
        Write-Note "  用 Word 打开导出的 .docx → 另存为 PDF（比装 LaTeX 省事得多）"
    } else {
        Write-Note "使用 $($latex.Source) 导出 PDF……"
        foreach ($rel in $Files) {
            $src = Join-Path $repoRoot $rel
            if (-not (Test-Path $src)) { continue }
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($src)
            $dstPdf = Join-Path $outFull "$baseName.pdf"
            & pandoc $src -f gfm -o $dstPdf --pdf-engine=xelatex -V CJKmainfont="Microsoft YaHei"
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] $baseName.pdf" -ForegroundColor Green
            } else {
                Write-Host "  [XX] $baseName.pdf 转换失败" -ForegroundColor Red
            }
        }
    }
}

# ---------------------------------------------------------------- 收尾
Write-Host ""
Write-Host "导出完成：成功 $okCount，失败 $failCount" -ForegroundColor Cyan
Write-Host ""
Write-Note "提醒："
Write-Note "  1. 导出物在 $OutDir\，那是产物，不要直接编辑"
Write-Note "  2. 导出前确认 docs/ 下是最终稿（改的是那里）"
Write-Note "  3. 课程还要求提交演示视频与 PPT，见 $OutDir\README.md 的清单"
Write-Host ""
