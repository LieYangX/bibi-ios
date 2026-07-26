# bibi-ios

WSL 双向同步 iOS 项目。在 **Windows 上编辑源码**，推送到 **WSL 中编译打包**。

## 目录结构

```
bibi-ios/
├── sync.ps1          # 双向同步脚本
├── dev.ps1           # 一键同步 + 构建
├── Package.swift
├── Sources/
│   └── bibi/
│       ├── ContentView.swift
│       └── bibiApp.swift
└── xtool.yml
```

## 使用方式

### 1. 在 Windows 上编辑源码

用 VS Code 或其他编辑器打开 `bibi-ios` 目录，直接修改 Swift 文件。

### 2. 同步 + 构建（一键完成）

在 `bibi-ios` 目录下打开 PowerShell，执行：

```powershell
# 同步修改到 WSL 并构建
.\dev.ps1

# 同步并安装到 USB 真机
.\dev.ps1 install

# 同步并预览
.\dev.ps1 dev

# 先清理构建缓存再构建
.\dev.ps1 clean
```

### 3. 手动同步

```powershell
# 从 WSL 拉取最新代码到本地
.\sync.ps1 to-win

# 推送本地修改到 WSL
.\sync.ps1 to-wsl

# 双向同步（先拉后推）
.\sync.ps1
```

### 4. 预览同步效果（不实际执行）

```powershell
.\sync.ps1 to-win -DryRun
```

## 典型工作流

```
1. VS Code 编辑 ContentView.swift（修改代码）
2. PowerShell 执行 .\dev.ps1 install（同步 + 安装到真机）
3. 查看 WSL 构建输出，如有错误回到第1步
```

## 注意事项

- 确保 WSL 中 `USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015` 已设置（参考之前的 xtool 文档）
- `sync.ps1` 本身不会被同步到 WSL（已排除）
- 编译产物（`.build`、`xtool/`、`Packages/`）不会同步，在 WSL 中重新生成
