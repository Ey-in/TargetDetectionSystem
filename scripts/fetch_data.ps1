<#
.SYNOPSIS
    下载并校验数据集

.DESCRIPTION
    数据集不入库（见 .gitignore），由本脚本统一拉取并校验 SHA256。
    校验和是为了保证 6 台机器拿到的是同一份数据 —— 数据不一致会导致
    "在我这 mAP 是 0.6，在你那是 0.4"这种查不出原因的问题。

    数据集选型确定后，请把「下载地址 + SHA256 + 许可证」写进：
      - data/README.md
      - docs/引用与第三方来源登记.md（数据集属于第三方来源，必须登记）

.PARAMETER Url
    下载地址

.PARAMETER Sha256
    期望的 SHA256 校验和（64 位十六进制，不区分大小写）

.PARAMETER OutFile
    保存路径，默认 data\dataset.zip

.PARAMETER Extract
    下载校验后自动解压到 data\ 下

.EXAMPLE
    .\scripts\fetch_data.ps1 -Url "https://example.com/data.zip" -Sha256 "abc123..."

.EXAMPLE
    # 只看本地文件现有校验和（用于填写上面的 -Sha256）
    Get-FileHash .\data\dataset.zip -Algorithm SHA256
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [Parameter(Mandatory = $true)]
    [string]$Sha256,

    [string]$OutFile = "data\dataset.zip",

    [switch]$Extract
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Write-Step    { param($m) Write-Host ""; Write-Host "=== $m ===" -ForegroundColor Cyan }
function Write-Ok      { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Note    { param($m) Write-Host "  [  ] $m" -ForegroundColor Gray }
function Write-Fail    { param($m) Write-Host "  [XX] $m" -ForegroundColor Red }

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if ($Sha256 -notmatch '^[0-9a-fA-F]{64}$') {
    Write-Fail "SHA256 格式不对，应为 64 位十六进制字符，当前传入的是：$Sha256"
    Write-Note "用 Get-FileHash <文件> -Algorithm SHA256 可以算出现有文件的校验和"
    exit 1
}

$target = Join-Path $repoRoot $OutFile
$targetDir = Split-Path -Parent $target
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

# ---------------------------------------------------------------- 1. 下载
Write-Step "1/3 下载数据集"
Write-Note "来源：$Url"
Write-Note "保存到：$target"

if (Test-Path $target) {
    Write-Note "文件已存在，跳过下载（如需重新下载请先手动删除）"
} else {
    try {
        # PS 5.1 的 Invoke-WebRequest 默认走系统代理，通常比 git 的网络环境宽松
        Invoke-WebRequest -Uri $Url -OutFile $target -UseBasicParsing
    } catch {
        Write-Fail "下载失败：$($_.Exception.Message)"
        Write-Note "若因网络受限，请确认代理 / VPN 正在运行后重试"
        exit 1
    }
    $sizeMB = [math]::Round((Get-Item $target).Length / 1MB, 1)
    Write-Ok "下载完成（$sizeMB MB）"
}

# ---------------------------------------------------------------- 2. 校验
Write-Step "2/3 校验 SHA256"

$actual = (Get-FileHash -Path $target -Algorithm SHA256).Hash
Write-Note "期望：$($Sha256.ToLower())"
Write-Note "实际：$($actual.ToLower())"

if ($actual -ne $Sha256.ToUpper() -and $actual -ne $Sha256.ToLower()) {
    Write-Fail "校验和不匹配！文件可能损坏，或来源已变更。"
    Write-Note "已删除损坏文件：$target"
    Remove-Item -Path $target -Force
    Write-Note "请确认下载地址与校验和是否正确（见 data/README.md）"
    exit 1
}
Write-Ok "校验通过"

# ---------------------------------------------------------------- 3. 解压
Write-Step "3/3 解压"

if ($Extract) {
    $extractDir = Join-Path $repoRoot "data"
    Write-Note "解压到：$extractDir"
    Expand-Archive -Path $target -DestinationPath $extractDir -Force
    Write-Ok "解压完成"
} else {
    Write-Note "未指定 -Extract，仅下载并校验，未解压"
    Write-Note "如需解压，加 -Extract 参数重跑"
}

Write-Host ""
Write-Ok "数据集就绪。注意：data/ 下的内容不会进入 git，这是有意为之。"

if (-not (Test-Path (Join-Path $repoRoot "docs\引用与第三方来源登记.md"))) {
    Write-Host ""
    Write-Note "提示：数据集属于第三方来源，请到 docs/引用与第三方来源登记.md 登记"
    Write-Note "      来源、许可证与获取方式（课程明确要求标注来源）。"
}
