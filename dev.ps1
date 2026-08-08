<#
.SYNOPSIS
  一键同步 + 构建脚本
.DESCRIPTION
  1. 将 Windows 的修改同步到 WSL
  2. 在 WSL 中执行 xtool dev 构建
  不需要手动切换环境。
.PARAMETER Command
  build  - 只构建不运行（默认）
  dev    - 构建并预览
  install - 构建并安装到 USB 设备
  clean  - 清理构建缓存后构建
.EXAMPLE
  .\dev.ps1            # 构建
  .\dev.ps1 install    # 构建并安装到真机
  .\dev.ps1 dev        # 构建并预览
#>

param(
    [ValidateSet("build", "dev", "install", "clean")]
    [string]$Command = "build"
)

$ErrorActionPreference = "Stop"

Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       bibi-ios 一键构建工具             ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan

# 第 1 步：同步 Windows → WSL
Write-Host "`n◆ 第1步：推送代码到 WSL..." -ForegroundColor Yellow

$syncScript = Join-Path -Path $PSScriptRoot -ChildPath "sync.ps1"
if (-not (Test-Path -LiteralPath $syncScript)) {
    Write-Host "  ✗ 找不到 sync.ps1" -ForegroundColor Red
    exit 1
}

& $syncScript -Direction to-wsl

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ 同步失败，取消构建" -ForegroundColor Red
    exit 1
}

# 第 2 步：设置环境变量后在 WSL 中构建
Write-Host "`n◆ 第2步：在 WSL 中执行 xtool $Command ..." -ForegroundColor Yellow
Write-Host ""

$projectDir = "/home/lieyang/ios-project/bibi"

switch ($Command) {
    "clean" {
        wsl bash -lc "cd $projectDir && export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015 && rm -rf .build xtool/.build && xtool dev build"
    }
    "build" {
        wsl bash -lc "cd $projectDir && export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015 && xtool dev build"
    }
    "dev" {
        wsl bash -lc "cd $projectDir && export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015 && xtool dev"
    }
    "install" {
        wsl bash -lc "cd $projectDir && export USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015 && xtool dev build --ipa && xtool install xtool/bibi.ipa --usb"
    }
}

# 第 3 步：构建成功后拉回产物到 Windows（方便分析构建日志）
Write-Host "`n◆ 第3步：拉取 WSL 编译产物到本地..." -ForegroundColor Yellow
& $syncScript -Direction to-win

Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  全部完成" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
