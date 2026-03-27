

# KuraliAll v2.2.0 — 全能 Linux 包管理器

> 在任意 Linux 发行版上，安装任意 Linux 发行版的离线软件包。
> 100% 离线工作，纯实现，零外部依赖。

## 📦 特性

| 特性 | 说明 |
|------|------|
| **全格式** | `.deb` `.rpm` `.pkg.tar.*` `.pacman` `.apk` `.kurali` `AppImage` `tar.*` `.zip` — 一个工具搞定 |
| **跨发行版** | Ubuntu 上装 RPM，Arch 上装 DEB，随便来 |
| **离线工作** | 不联网、不检查更新、不下载依赖 |
| **文件备份** | 安装前自动备份被覆盖的文件 |
| **依赖检查** | `ldd` 检查缺失的库文件 |
| **RAM 模式** | 内存运行，退出即清理，不污染系统 |
| **Docker 兜底** | 本地失败自动转容器 |
| **桌面集成** | 自动生成 `.desktop` 文件 |
| **服务管理** | systemd 自启控制 |
| **WebUI** | 浏览器图形界面，拖拽安装、实时日志、依赖检查 |
| **23 种发行版** | Debian/Ubuntu/RHEL/Fedora/Arch/Alpine/openSUSE/... |

## 🚀 快速开始

```bash
# 解压
unzip KuraliAll.zip && cd KuraliAll

# 方式1：直接用（不需要安装）
sudo bash kuraliAll.sh i myapp.deb

# 方式2：安装到系统（之后用 kurali 命令）
sudo bash install.sh
kurali i myapp.rpm
kurali i myapp.AppImage
kurali i software.tar.xz

# 方式3：启动 WebUI（浏览器图形界面）
sudo python3 kuraliAll-webui.py
# 浏览器打开 http://localhost:8080
```

## 📁 项目结构

```
KuraliAll/
├── kuraliAll.sh        # Shell 版主程序（推荐）
├── kuraliAll.py        # Python 版（等价功能）
├── kuraliAll-gui.py    # 终端 GUI 版（curses）
├── kuraliAll-webui.py  # WebUI 版（浏览器图形界面）🆕
├── install.sh          # 一键安装脚本
├── README.md           # 本文件
├── USAGE.md            # 详细使用手册
├── config/
│   └── distros.txt     # 23 种发行版数据库
├── modules/
│   ├── core.mod        # 核心：常量、日志、模块加载、备份
│   ├── system.mod      # 发行版检测、原生包管理器
│   ├── pkg-handler.mod # 统一包格式处理（8种格式+Alpine .apk）
│   ├── ram-run.mod     # 内存运行模式
│   ├── docker-run.mod  # Docker 容器兜底
│   ├── desktop.mod     # 桌面集成
│   └── service.mod     # 服务管理
└── hooks/
    ├── pre-install.mod  # 安装前钩子
    └── post-install.mod # 安装后钩子
```

## 🎮 命令速查

```bash
# 安装
kurali i <文件>                    # 安装软件包
kurali i --system <文件>           # 直接安装到系统路径 ⚠ 危险
kurali i --ram <文件>              # RAM 模式运行（不安装）

# 管理
kurali r <包名>                    # 卸载
kurali l                           # 列出已安装
kurali s <关键词>                   # 搜索
kurali f <包名>                     # 查看详情
kurali deps                        # 检查系统依赖
kurali deps /usr/bin/xxx           # 检查程序依赖
kurali pack <文件>                   # 打包为 .kurali 格式
kurali pack <文件> output.kurali    # 指定输出文件名

# 系统
kurali native <包名>               # 调原生包管理器
kurali boot enable <服务>          # 服务自启
kurali update                      # 版本信息
kurali help                        # 帮助

# WebUI
python3 kuraliAll-webui.py         # 启动 WebUI（默认 0.0.0.0:8080）
python3 kuraliAll-webui.py -p 9090 # 自定义端口
python3 kuraliAll-webui.py -h 127.0.0.1 # 仅本地访问
```

## 🖥️ 四个版本

| 版本 | 文件 | 特点 |
|------|------|------|
| **Shell** | `kuraliAll.sh` | 推荐，零依赖，任何 Linux 都能跑 |
| **Python** | `kuraliAll.py` | 需要 Python 3.6+，功能等价 |
| **GUI** | `kuraliAll-gui.py` | 终端图形界面（curses），无需 X11 |
| **WebUI** 🆕 | `kuraliAll-webui.py` | 浏览器图形界面，拖拽安装、实时日志、零外部依赖 |

### WebUI 功能一览

- 📂 **拖拽安装** — 将软件包文件拖到浏览器即可安装
- 🛡️ **三种模式** — 安全模式（沙箱）、系统安装、RAM 模式
- 📋 **包管理** — 查看已安装列表、搜索、查看详情、一键卸载
- 🖥️ **实时日志** — 操作过程实时显示，终端风格
- 🔍 **依赖检查** — 系统依赖 + 程序依赖检查
- 💾 **备份管理** — 查看和管理安装前的文件备份
- 📝 **系统日志** — 完整操作记录
- 📦 **原生安装** — 调用 apt/yum/dnf/pacman 等
- 📦 **打包工具** — 一键将任意格式打包为 .kurali
- 📊 **系统信息** — 发行版、内核、磁盘使用情况

## 🌐 支持的发行版

Debian · Ubuntu · Linux Mint · Pop!_OS · Kali · elementary
RHEL · CentOS · Rocky · AlmaLinux · Fedora · Oracle Linux
Arch · Manjaro · EndeavourOS · Artix
Alpine · openSUSE · SLES · Void · Solus · NixOS · Gentoo

## ⚠️ 危险操作标注

| 操作 | 风险 | 说明 |
|------|------|------|
| `--system` | 🔴 高 | 直接复制文件到系统路径，可能覆盖系统文件 |
| `kurali r` (system 模式) | 🔴 高 | 从系统路径删除文件 |
| `kurali boot disable` | 🟡 中 | 禁用服务可能导致功能失效 |
| 维护脚本执行 | 🟡 中 | deb/rpm 的 preinst/postinst 会自动执行，无沙箱 |
| 默认安装 | 🟢 低 | 隔离目录 + 符号链接，不影响系统 |

## 📋 WebUI 更新日志

### v2.2.0 — WebUI 版本 🆕

| # | 类型 | 内容 |
|---|------|------|
| 1 | 🆕 功能 | 新增 `kuraliAll-webui.py` — 浏览器图形界面 |
| 2 | 🆕 功能 | 拖拽安装：将软件包文件拖到浏览器即可一键安装 |
| 3 | 🆕 功能 | 三种安装模式：安全模式（沙箱）、系统安装、RAM 模式 |
| 4 | 🆕 功能 | 包管理界面：列表、搜索、详情查看、一键卸载 |
| 5 | 🆕 功能 | 实时终端日志：安装/卸载过程实时输出 |
| 6 | 🆕 功能 | 依赖检查：系统依赖和程序依赖检查 |
| 7 | 🆕 功能 | 备份管理：查看、删除、清空文件备份 |
| 8 | 🆕 功能 | 原生安装：通过 WebUI 调用系统包管理器 |
| 9 | 🆕 功能 | 打包工具：在线将任意格式打包为 .kurali |
| 10 | 🆕 功能 | 系统信息面板：发行版、内核、磁盘使用一览 |
| 11 | 🔧 改进 | 全版本号升级至 2.2.0 |
| 12 | 📝 说明 | WebUI 纯 Python 标准库实现，零外部依赖，离线可用 |

### v2.1.2 — Bug 修复

| # | 模块 | 严重度 | 修复 |
|---|------|--------|------|
| 1 | install.sh | 🔴 高 | 安装后添加 `chmod +x kuraliAll.sh`，修复 Permission denied |
| 2 | install.sh | 🟡 中 | 版本号从 `2.0.0` 同步为 `2.1.0` |
| 3 | kuraliAll.sh | 🟡 中 | `--install-self` 同样添加 `chmod +x` |
| 4 | kuraliAll.py | 🟡 中 | `deps` 命令在 `ldconfig` 不可用时回退到常见库路径搜索 |
| 5 | kuraliAll.py | 🟡 中 | deb/rpm 包名提取改用 `dpkg-deb -f` / `rpm -qp` |

### v2.1.1 — 备用方案 + Docker 适配

| # | 模块 | 改动 |
|---|------|------|
| 1 | docker-run.mod | 完全重写：支持 Podman、自动选基础镜像、容器内自动安装、构建失败挂载兜底 |
| 2 | service.mod | 完全重写：支持 systemd/OpenRC/runit/sysvinit 四种 init 系统自动检测 |
| 3 | pkg-handler.mod | deb 提取加 python3 备用、RPM 包名 python3 解析、AppImage unsquashfs 备用 |
| 4 | ram-run.mod | /tmp 文件系统类型检测 + 提示 |
| 5 | desktop.mod | xdg-desktop-menu 刷新备用 |

### v2.1.0 — Alpine .apk 支持

| # | 类型 | 内容 |
|---|------|------|
| 1 | 🆕 功能 | Python 版支持 .apk 格式（Alpine Linux 包），含 .PKGINFO 元数据解析 |
| 2 | 🆕 功能 | GUI 版支持 .apk 格式 |
| 3 | 🆕 功能 | Python 版安装时自动提取版本号（deb: dpkg-deb, apk: .PKGINFO） |
| 4 | 📝 文档 | 三个版本的帮助文本统一添加 .apk 格式说明 |

### v2.0 — 核心重写

| # | 严重度 | Bug | 修复 |
|---|--------|-----|------|
| 1 | 🔴 高 | RPM 解压不支持 XZ 压缩的 payload | 新增 XZ/gzip/bzip2/zstd 四种压缩检测，Python lzma/gzip/bz2 回退 |
| 2 | 🟡 中 | pacman .PKGINFO 的 `pkgver = x.x-x`（等号有空格）解析失败 | 改用 `grep -E` + `sed` 解析，兼容两种格式 |
| 3 | 🟢 低 | `manifest.json.tmp` 残留在 .kurali 包中 | 改为直接修改 manifest.json |
| 4 | 🟢 低 | AppImage symlink 用 "AppRun" 而非包名 | AppImage 格式时用包名作 symlink |
| 5 | 🟢 低 | `system.mod` 独立 source 时 `has_cmd` 未定义 | 添加 `declare -F` 检查 + `command -v` 回退 |

## 🧪 真实包测试覆盖

| 软件 | 格式 | 大小 | 文件数 | 结果 |
|------|------|------|--------|------|
| librsvg2-bin 2.58.0 | .deb | 2.2MB | 4 | ✅ |
| QQ 3.2.26 | .deb | 166MB | 1451 | ✅ |
| QQ 3.2.26 | .rpm | 168MB | 1451 | ✅ (修复后) |
| WeChat 4.1.1 | AppImage | 276MB | 138 | ✅ |
| StarVPN 5.2.6 | .deb | 12MB | 3 | ✅ |
| figlet 2.2.5 | .apk (Alpine) | 118K | 65 | ✅ |

> ⚠️ `.apk` 是 **Alpine Linux** 的包格式（Alpine Package Keeper），**不是安卓 APK**。

## 📄 许可

自行查看