<#
.SYNOPSIS
    一键搭建开发环境（软件工程实验 · 课题九 目标检测系统）

.DESCRIPTION
    依次完成：
      1. 检查 conda，创建 Python 3.12 环境
      2. 安装依赖，并生成锁定版本的 requirements.lock.txt
      3. 配置本仓库的 git 设置（hooks、中文路径显示、长路径）
      4. 检查提交身份是否能关联到 GitHub 账号

.EXAMPLE
    .\scripts\setup-dev.ps1

.EXAMPLE
    .\scripts\setup-dev.ps1 -EnvName tds2 -SkipInstall
#>
[CmdletBinding()]
param(
    [string]$EnvName = "tds",
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"

# PowerShell 5.1 控制台默认 GBK，git 输出 UTF-8 会变乱码
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Write-Step    { param($m) Write-Host ""; Write-Host "=== $m ===" -ForegroundColor Cyan }
function Write-Ok      { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Note    { param($m) Write-Host "  [  ] $m" -ForegroundColor Gray }
function Write-Caution { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Write-Fail    { param($m) Write-Host "  [XX] $m" -ForegroundColor Red }

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host ""
Write-Host "目标检测系统 —— 开发环境搭建" -ForegroundColor White
Write-Note "仓库位置：$repoRoot"

# ---------------------------------------------------------------- 1. conda
Write-Step "1/5 检查 conda"

$condaCmd = Get-Command conda -ErrorAction SilentlyContinue
if (-not $condaCmd) {
    Write-Fail "未找到 conda。"
    Write-Note "请先安装 Miniconda 或 Anaconda，重开终端后重试。"
    Write-Note "下载：https://docs.conda.io/en/latest/miniconda.html"
    exit 1
}
Write-Ok "conda：$($condaCmd.Source)"

# 路径含中文会让 OpenCV 静默失败，这里先拦一道
if ($repoRoot -match '[^\x00-\x7F]') {
    Write-Caution "仓库路径含非 ASCII 字符：$repoRoot"
    Write-Caution "OpenCV 的 imread/imwrite 在中文路径下会静默返回 None，不报错。"
    Write-Caution "强烈建议移到纯英文路径，例如 F:\se\TargetDetectionSystem"
    Write-Host ""
    $answer = Read-Host "  仍要继续吗？(y/N)"
    if ($answer -ne "y" -and $answer -ne "Y") { exit 1 }
} else {
    Write-Ok "路径为纯 ASCII，不会触发 OpenCV 中文路径问题"
}

# ---------------------------------------------------------------- 2. 环境
Write-Step "2/5 检查 conda 环境 [$EnvName]"

$envList = & conda env list
$envExists = $false
foreach ($line in $envList) {
    if ($line -match "^\s*$([regex]::Escape($EnvName))\s") { $envExists = $true; break }
}

if ($envExists) {
    Write-Ok "环境 [$EnvName] 已存在"
} else {
    Write-Note "创建环境 [$EnvName]（Python 3.12）……"
    & conda create -y -n $EnvName python=3.12
    if ($LASTEXITCODE -ne 0) { Write-Fail "创建环境失败"; exit 1 }
    Write-Ok "环境创建完成"
}

# ---------------------------------------------------------------- 3. 依赖
Write-Step "3/5 安装依赖"

if ($SkipInstall) {
    Write-Caution "按要求跳过依赖安装"
} else {
    Write-Note "升级 pip……"
    # --no-capture-output 让 pip 的进度实时显示，否则装 torch 时会长时间没有任何输出
    & conda run --no-capture-output -n $EnvName python -m pip install --upgrade pip

    Write-Note "安装 requirements.txt 与 requirements-dev.txt……"
    Write-Caution "首次安装会下载 PyTorch，体积较大（1~2GB），请耐心等待"
    & conda run --no-capture-output -n $EnvName python -m pip install -r requirements.txt -r requirements-dev.txt
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "依赖安装失败。常见原因："
        Write-Note "  1. 网络问题 —— 试配置代理后重试"
        Write-Note "  2. 需要 CUDA 版 PyTorch —— 见 README 或问技术经理"
        exit 1
    }
    Write-Ok "依赖安装完成"

    # 生成锁定版本：6 台机器必须装出完全一致的环境
    # 注意这里不能用 --no-capture-output，否则管道拿不到输出
    Write-Note "生成 requirements.lock.txt……"
    & conda run -n $EnvName python -m pip freeze | Out-File -FilePath "requirements.lock.txt" -Encoding ascii
    Write-Ok "已生成 requirements.lock.txt"

    Write-Caution "请把 requirements.lock.txt 提交到仓库，组员一律按它安装"
}

# ---------------------------------------------------------------- 4. git
Write-Step "4/5 配置 git"

& git config core.hooksPath .githooks
Write-Ok "已启用本地钩子 core.hooksPath = .githooks"

# 中文文件名默认显示成八进制转义（如 \350\260\203...），看着很痛苦
& git config core.quotePath false
Write-Ok "已设置 core.quotePath = false（git status 可正常显示中文文件名）"

& git config core.longpaths true
Write-Ok "已设置 core.longpaths = true"

# ---------------------------------------------------------------- 5. 身份
Write-Step "5/5 检查提交身份"

$gitName = & git config user.name
$gitEmail = & git config user.email

if (-not $gitName -or -not $gitEmail) {
    Write-Fail "尚未配置 git 提交身份，请先执行："
    Write-Note '  git config --global user.name  "你的名字"'
    Write-Note '  git config --global user.email "你的邮箱"'
} else {
    Write-Ok "当前身份：$gitName <$gitEmail>"
    Write-Host ""
    Write-Caution "请务必核对：该邮箱是否已在你的 GitHub 账号中「添加并验证」？"
    Write-Note "  核对地址：https://github.com/settings/emails"
    Write-Note "  没验证的后果：提交不会关联到你的账号，贡献统计无法被核实 ——"
    Write-Note "  而「版本控制日志」正是课程点名要的工作量证明。"
    Write-Note ""
    Write-Note "  若无法验证该邮箱，改用 GitHub 提供的 noreply 地址，并执行："
    Write-Note '    git config user.email "<你的 noreply 地址>"'
}

# ---------------------------------------------------------------- 收尾
Write-Host ""
Write-Host "=== 完成 ===" -ForegroundColor Cyan
Write-Host ""
Write-Note "下一步："
Write-Note "  1. 读一遍 CONTRIBUTING.md（分支、commit、PR 规范）"
Write-Note "  2. 在 docs/开发计划.md 找到自己的任务"
Write-Note "  3. 从最新的 main 切分支： git checkout main; git pull; git checkout -b feat/xxx"
Write-Host ""
Write-Note "激活环境：conda activate $EnvName"
Write-Host ""
