# KuraliAll — 全能 Linux 包管理器

> 在任意 Linux 发行版上，安装任意 Linux 发行版的离线软件包。
> 100% 离线工作，**纯 Shell 实现**，零外部依赖（无 Python/Node/...）。

## 📦 特性

| 特性 | 说明 |
|------|------|
| **全格式** | `.deb` `.rpm` `.pkg.tar.*` `.pacman` `.apk` `.kurali` `AppImage` `tar.*` `.zip` |
| **跨发行版** | Ubuntu 上装 RPM，Arch 上装 DEB |
| **离线工作** | 不联网、不检查更新、不下载依赖 |
| **文件备份** | 安装前自动备份被覆盖的文件 |
| **依赖检查** | `ldd` 检查缺失的库文件 |
| **RAM 模式** | 内存运行，退出即清理，不污染系统 |
| **Docker 兜底** | 本地失败自动转容器 |
| **桌面集成** | 自动生成 `.desktop` 文件 |
| **服务管理** | systemd/OpenRC/runit/sysvinit 自启控制 |
| **23 种发行版** | Debian/Ubuntu/RHEL/Fedora/Arch/Alpine/openSUSE/... |

## 🚀 快速开始

```bash
git clone https://gitee.com/AY77-OP/kurali-all.git
cd kurali-all

# 方式1：直接用
sudo bash kuraliAll.sh i myapp.deb

# 方式2：安装到系统
sudo bash install.sh
kurali i myapp.rpm
kurali i myapp.AppImage
```

## 📁 项目结构

```
kurali-all/
├── kuraliAll.sh        # 主程序
├── install.sh          # 一键安装脚本
├── config/
│   └── distros.txt     # 23 种发行版数据库
├── modules/
│   ├── core.mod        # 核心：常量、日志、模块加载
│   ├── system.mod      # 发行版检测、原生包管理器
│   ├── pkg-handler.mod # 统一包格式处理（8 种格式）
│   ├── ram-run.mod     # 内存运行模式
│   ├── docker-run.mod  # Docker/Podman 兜底
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
kurali i --system <文件>           # 直接安装到系统路径 ⚠
kurali i --ram <文件>              # RAM 模式运行

# 管理
kurali r <包名>                    # 卸载
kurali l                           # 列出已安装
kurali s <关键词>                   # 搜索
kurali f <包名>                    # 查看详情
kurali deps                        # 检查系统依赖
kurali pack <文件>                 # 打包为 .kurali 格式

# 系统
kurali native <包名>               # 调原生包管理器
kurali boot enable <服务>          # 服务自启
kurali update                      # 版本信息
```

## ⚠️ 注意事项

- `.apk` 是 **Alpine Linux** 包格式，不是安卓 APK
- `--system` 模式会直接修改系统文件，有风险
- 纯 Shell 实现，不需要 Python、Node.js 等运行时

## 📋 更新日志

### v3.0.0 — 纯 Shell 重构

- 🔧 移除所有 Python3 依赖，100% 纯 Shell
- 🔧 RPM 解压统一使用 xxd + cpio 纯 Shell 方案
- 🧹 精简模块代码，移除冗余逻辑
- 📝 统一错误提示和输出格式

### v2.3.0 — Shell 版本（含 Python 兜底）

- 🔧 重构为 Shell 版本，移除 Python GUI/WebUI

## 📄 许可

木兰宽松许可证，第2版 (Mulan PSL v2)
