
# KuraliAll — 全能 Linux 包管理器

> 在任意 Linux 发行版上，安装任意 Linux 发行版的离线软件包。
> 100% 离线工作，纯 Shell 实现，零外部依赖。

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
| **23 种发行版** | Debian/Ubuntu/RHEL/Fedora/Arch/Alpine/openSUSE/... |

## 🚀 快速开始

```bash
# 解压或克隆
git clone https://gitee.com/AY77-OP/kurali-all.git
cd kurali-all

# 方式1：直接用（不需要安装）
sudo bash kuraliAll.sh i myapp.deb

# 方式2：安装到系统（之后用 kurali 命令）
sudo bash install.sh
kurali i myapp.rpm
kurali i myapp.AppImage
kurali i software.tar.xz
```

## 📁 项目结构

```
kurali-all/
├── kuraliAll.sh        # 主程序
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
```

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

## 📋 更新日志

### v2.3.0 — Shell 重构版

- 🔧 重构为纯 Shell 版本，移除 Python/GUI/WebUI
- 📦 精简项目结构，保留模块化架构
- 📝 更新文档，统一为单版本说明

### v2.2.0 — WebUI 版本

- 🆕 WebUI 浏览器图形界面（已移除）

### v2.1.x — 稳定版

- 🆕 Alpine .apk 支持
- 🔧 RPM 解压支持 XZ/gzip/bzip2/zstd
- 🐛 安装后 chmod 修复

### v2.0 — 核心重写

- RPM 纯 Shell 解压
- 多格式统一处理
- 依赖检查、Docker 兜底

## 📄 许可

木兰宽松许可证，第2版 (Mulan PSL v2)
