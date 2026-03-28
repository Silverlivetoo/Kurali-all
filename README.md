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
| **自动提权** | 忘记 sudo 也不怕，自动重新执行 |
| **23 种发行版** | Debian/Ubuntu/RHEL/Fedora/Arch/Alpine/openSUSE/... |

## 🚀 快速开始

```bash
git clone https://gitee.com/AY77-OP/kurali-all.git
cd kurali-all

# 方式1：直接用
bash kuraliAll.sh i myapp.deb

# 方式2：安装到系统（之后用 kurali 命令）
bash kuraliAll.sh --install-self
kurali i myapp.rpm
kurali i myapp.AppImage

# 卸载 KuraliAll（会保留已安装的包数据）
kurali uninstall-self
```

> 所有需要 root 权限的命令会**自动提权**，无需手动加 `sudo`。

## 📁 项目结构

```
kurali-all/
├── kuraliAll.sh        # 主程序（含安装功能 --install-self）
├── install.sh          # 独立安装脚本 (sudo bash install.sh)
├── USAGE.md            # 详细使用手册
├── config/
│   └── distros.txt     # 23 种发行版数据库
├── modules/
│   ├── core.mod        # 核心：常量、日志、模块加载
│   ├── system.mod      # 发行版检测、原生包管理器
│   ├── pkg-handler.mod # 统一包格式处理（8 种格式）
│   ├── docker-run.mod  # Docker/Podman 兜底
│   ├── desktop.mod     # 桌面集成
│   ├── service.mod     # 服务管理
│   └── update.mod      # 联网自更新
└── hooks/
    ├── pre-install.mod  # 安装前钩子
    └── post-install.mod # 安装后钩子
```

## 🎮 命令速查

```bash
# 安装
kurali i <文件>                    # 安装软件包
kurali i --system <文件>           # 直接安装到系统路径 ⚠

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
kurali self-update                 # 联网自更新
kurali network status              # 查看联网许可状态
kurali network revoke              # 撤销联网许可
```

## ⚠️ 注意事项

- `.apk` 是 **Alpine Linux** 包格式，不是安卓 APK
- `--system` 模式会直接修改系统文件，有风险
- 纯 Shell 实现，不需要 Python、Node.js 等运行时

## 📋 更新日志

### v3.1.0 — 自动提权与卸载

- ✨ 新增自动提权：需要 root 的命令自动 `sudo` 重新执行，不用手动加了
- ✨ 新增 `kurali uninstall-self` 卸载命令（与 `--install-self` 对称）
- 🐛 修复 `install.sh` 版本号读取失败（grep 匹配模式错误）
- 🐛 修复 `self-update` 缺少 `need_root` 导致自动提权不生效

### v3.0.1 — Bug 修复与新功能

- ✨ 新增 `self-update` 联网自更新（需用户授权，支持 git pull / zip 下载）
- ✨ 新增 `network status|grant|revoke` 联网许可管理
- 🐛 修复 deb 包解压后二进制权限丢失导致桌面图标无法启动
- 🐛 修复桌面图标搜索范围过窄，改为全目录递归搜索（适配 /opt 等非标准路径）
- 🐛 修复 AppImage 安装后无桌面图标，自动查找 AppRun 生成 .desktop
- 🐛 修复 AppImage 包名包含架构后缀（如 _x86_64），自动清理

### v3.0.0 — 纯 Shell 重构

- 🔧 移除所有 Python3 依赖，100% 纯 Shell
- 🔧 RPM 解压统一使用 xxd + cpio 纯 Shell 方案
- 🧹 精简模块代码，移除冗余逻辑
- 📝 统一错误提示和输出格式

### v2.3.0 — Shell 版本（含 Python 兜底）

- 🔧 重构为 Shell 版本，移除 Python GUI/WebUI

## 📄 许可

木兰宽松许可证，第2版 (Mulan PSL v2)
