<#
.SYNOPSIS
  WSL ↔ Windows 双向同步脚本
.DESCRIPTION
  在 WSL (~/ios-project/bibi) 和 Windows (本目录) 之间双向同步 iOS 项目源码。
  使用 rsync 增量传输，只同步变更文件，不走全量复制。
.PARAMETER Direction
  同步方向：
    to-win  - WSL → Windows（拉取 WSL 最新代码到本目录）
    to-wsl  - Windows → WSL（推送本目录修改到 WSL）
    both    - 先拉后推，保证两端一致（默认）
.PARAMETER DryRun
  试运行模式，只显示会同步哪些文件，不实际执行
.EXAMPLE
  .\sync.ps1                  # 双向同步（默认）
  .\sync.ps1 to-win           # 只从 WSL 拉取
  .\sync.ps1 to-wsl           # 只推送到 WSL
  .\sync.ps1 to-win -DryRun   # 查看 WSL 有哪些差异
#>

param(
    [ValidateSet("to-win", "to-wsl", "both")]
    [string]$Direction = "both",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# WSL 用户名（和 home 目录路径）
$WSLUser = "lieyang"
$WSLProject = "/home/$WSLUser/ios-project/bibi"

# Windows 本目录（脚本所在目录）
$WinProject = $PSScriptRoot

# WSL 中的 Windows 路径映射
$WinPathInWSL = "/mnt/c/Users/$env:UserName/open-worker/bibi-ios"

# rsync 排除规则（不同步编译产物和系统文件）
# 注意：sync.ps1 只在 Windows 端存在，必须排除，否则会被 --delete 删掉
$Excludes = @(
    "sync.ps1",
    ".build",
    ".sourcekit-lsp",
    ".git",
    "*.ipa",
    "*.app",
    "Packages",
    "xtool",
    "doc"
)

# ============================================================
# 确保 WSL 中有 rsync
# ============================================================
function Ensure-Rsync {
    $hasRsync = wsl bash -c "which rsync 2>/dev/null" | Out-String
    if ([string]::IsNullOrWhiteSpace($hasRsync)) {
        Write-Host "» WSL 中未安装 rsync，正在安装..." -ForegroundColor Yellow
        wsl sudo apt-get update -qq
        wsl sudo apt-get install -y -qq rsync
        Write-Host "  ✓ rsync 安装完成" -ForegroundColor Green
    }
}

# ============================================================
# 构建 rsync 参数
# ============================================================
function Get-RsyncArgs {
    param([string]$Source, [string]$Dest)

    $args = "-avz"   # 归档模式 + 压缩传输 + 显示进度
    $args += " --delete"   # 删除目标端多余文件（保持精确一致）
    $args += " --progress" # 显示每个文件的传输进度

    if ($DryRun) {
        $args += " --dry-run"
    }

    # 添加排除规则
    foreach ($ex in $Excludes) {
        $args += " --exclude='$ex'"
    }

    # 添加源和目标
    $args += " '$Source' '$Dest'"

    return $args
}

# ============================================================
# 同步方向：WSL → Windows
# ============================================================
function Sync-ToWin {
    Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  方向：WSL → Windows" -ForegroundColor Cyan
    Write-Host "  源 ：$WSLProject" -ForegroundColor Cyan
    Write-Host "  目标：$WinProject" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════`n" -ForegroundColor Cyan

    $source = "$WSLProject/"
    $dest = "$WinPathInWSL/"
    $args = Get-RsyncArgs -Source $source -Dest $dest

    $command = "rsync $args"
    Write-Host "执行：$command" -ForegroundColor DarkGray

    wsl bash -c $command

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n  ✓ WSL → Windows 同步完成" -ForegroundColor Green
    } else {
        Write-Host "`n  ✗ 同步出错，退出码：$LASTEXITCODE" -ForegroundColor Red
    }
}

# ============================================================
# 同步方向：Windows → WSL
# ============================================================
function Sync-ToWsl {
    Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  方向：Windows → WSL" -ForegroundColor Cyan
    Write-Host "  源 ：$WinProject" -ForegroundColor Cyan
    Write-Host "  目标：$WSLProject" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════`n" -ForegroundColor Cyan

    $source = "$WinPathInWSL/"
    $dest = "$WSLProject/"
    $args = Get-RsyncArgs -Source $source -Dest $dest

    $command = "rsync $args"
    Write-Host "执行：$command" -ForegroundColor DarkGray

    wsl bash -c $command

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n  ✓ Windows → WSL 同步完成" -ForegroundColor Green
    } else {
        Write-Host "`n  ✗ 同步出错，退出码：$LASTEXITCODE" -ForegroundColor Red
    }
}

# ============================================================
# 主流程
# ============================================================
try {
    Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║       bibi-ios 项目同步工具              ║" -ForegroundColor Cyan
    Write-Host "║       WSL ↔ Windows 双向同步             ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "`n☞ 试运行模式（不会实际同步）" -ForegroundColor Yellow
    }

    # 确保 WSL 中有 rsync
    Ensure-Rsync

    # 检查 WSL 项目目录是否存在
    $wslExists = wsl bash -c "test -d $WSLProject && echo ok" | Out-String
    if ([string]::IsNullOrWhiteSpace($wslExists)) {
        Write-Host "`n✗ WSL 项目目录不存在：$WSLProject" -ForegroundColor Red
        Write-Host "  请先在 WSL 中创建项目" -ForegroundColor Yellow
        exit 1
    }

    # 检查源目录
    if (-not (Test-Path -LiteralPath $WinProject)) {
        Write-Host "`n✗ 本机目录不存在：$WinProject" -ForegroundColor Red
        exit 1
    }

    switch ($Direction) {
        "to-win" { Sync-ToWin }
        "to-wsl" { Sync-ToWsl }
        "both" {
            Sync-ToWin
            Sync-ToWsl
            Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Cyan
            Write-Host "  双向同步全部完成" -ForegroundColor Cyan
            Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
        }
    }
}
catch {
    Write-Host "`n✗ 脚本出错：$_" -ForegroundColor Red
    exit 1
}
