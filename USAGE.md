# KuraliAll — 详细使用手册

## 目录

1. [安装 KuraliAll](#1-安装-kuraliall)
2. [安装软件包](#2-安装软件包)
3. [卸载软件包](#3-卸载软件包)
4. [查看已安装](#4-查看已安装)
5. [搜索软件包](#5-搜索软件包)
6. [查看包详情](#6-查看包详情)
7. [依赖检查](#7-依赖检查)
8. [RAM 模式](#8-ram-模式)
9. [系统安装模式](#9-系统安装模式)
10. [Docker 兜底](#10-docker-兜底)
11. [服务管理](#11-服务管理)
12. [原生包管理器](#12-原生包管理器)
13. [发行版指定](#13-发行版指定)
14. [.kurali 格式](#14-kurali-格式)
15. [配置与环境变量](#15-配置与环境变量)
16. [故障排除](#16-故障排除)

---

## 1. 安装 KuraliAll

### 方式一：直接使用（不安装）

```bash
cd kurali-all
sudo bash kuraliAll.sh i <文件>
```

### 方式二：安装到系统

```bash
cd kurali-all
sudo bash install.sh
```

安装后：
- 入口：`/usr/local/bin/kurali`
- 数据：`/var/lib/kuraliAll/`
- 使用：`kurali help`

### 方式三：自安装

```bash
sudo bash kuraliAll.sh --install-self
```

---

## 2. 安装软件包

### 基本语法

```bash
kurali i <文件>
```

### 支持格式

| 格式 | 示例 |
|------|------|
| .deb | `kurali i google-chrome.deb` |
| .rpm | `kurali i vscode.rpm` |
| pacman | `kurali i xxx.pkg.tar.zst` |
| .apk (Alpine) | `kurali i figlet.apk` |
| AppImage | `kurali i balenaEtcher.AppImage` |
| tar | `kurali i node-v20.tar.xz` |
| zip | `kurali i myapp.zip` |
| .kurali | `kurali i myapp.kurali` |

> ⚠️ `.apk` 是 **Alpine Linux** 的包格式（Alpine Package Keeper），**不是安卓 APK**。

### 安装模式

**默认模式（推荐）：**
- 文件解压到隔离目录 `/var/lib/kuraliAll/pkg/<name>/rootfs/`
- 自动创建符号链接到 `/usr/local/bin/`
- **不影响系统**，卸载干净

**系统模式（⚠ 危险）：**
```bash
kurali i --system <文件>
```
- 直接复制文件到 `/usr/bin/` `/usr/lib/` 等系统路径
- 会覆盖同名文件（有备份）
- 需要 root 权限
- **可能导致系统不稳定**

### 自动备份

默认安装时，如果覆盖已有文件，会自动备份到：
```
/var/lib/kuraliAll/backup/<路径>.<时间戳>.bak
```

关闭备份：`kurali i --no-backup <文件>`

---

## 3. 卸载软件包

```bash
kurali r <包名>
```

系统模式安装的包卸载时会提示确认。

---

## 4. 查看已安装

```bash
kurali l
```

输出示例：
```
包名                 格式         版本       模式       安装日期
myapp                deb          1.2.3      sandbox    2025-03-26
firefox              tar          121.0      sandbox    2025-03-26
```

---

## 5. 搜索软件包

```bash
kurali s <关键词>
```

按包名模糊匹配，不区分大小写。

---

## 6. 查看包详情

```bash
kurali f <包名>
```

显示：包名、版本、格式、安装日期、安装路径、文件数量、占用空间。

---

## 7. 依赖检查

### 检查系统依赖

```bash
kurali deps
```

### 检查程序依赖

```bash
kurali deps /usr/bin/myapp
```

用 `ldd` 检查程序需要哪些库，哪些缺失。

---

## 8. RAM 模式

在内存中临时运行程序，不安装、不写磁盘。

```bash
kurali run <文件>
# 或
kurali --ram <文件>
```

**工作原理：**
- 解压到 `/dev/shm` 或 `/run/user/$UID`（tmpfs = 内存盘）
- 设置 `LD_LIBRARY_PATH` 和 `PATH`
- 退出时自动清理

**适合场景：**
- 测试软件包
- 临时使用工具
- 不想污染系统

---

## 9. 系统安装模式

```bash
kurali i --system <文件>
```

**⚠ 警告：此操作会直接修改系统文件**

- 文件复制到 `/usr/bin/`、`/usr/lib/`、`/etc/` 等
- 覆盖同名文件（自动备份到 `/var/lib/kuraliAll/backup/`）
- 执行包内的 preinst/postinst 脚本
- 更新 ldconfig 缓存

---

## 10. Docker 兜底

当安装失败时，可选择 Docker 容器运行：

```bash
kurali i --docker <文件>    # 失败时自动提示
kurali docker <包名>        # 将已安装包转为容器
```

---

## 11. 服务管理

```bash
kurali boot enable <服务名>    # 开机自启
kurali boot disable <服务名>   # 取消自启
kurali boot status <服务名>    # 查看状态
```

---

## 12. 原生包管理器

调用系统原生包管理器安装：

```bash
kurali native htop
kurali native vim
```

自动检测发行版，调用 apt/yum/dnf/pacman 等。

---

## 13. 发行版指定

```bash
kurali --distro=arch i <文件>    # 强制用 Arch 方式处理
kurali --select-distro           # 交互式选择
```

---

## 14. .kurali 格式

`.kurali` 是 KuraliAll 自己的软件包格式，可以把任意支持的格式统一转换。

### 打包

```bash
# 自动命名（包名-版本.kurali）
kurali pack ./myapp.deb

# 指定输出文件名
kurali pack ./myapp.deb myapp-custom.kurali
```

### .kurali 结构

```
package.kurali (tar.gz)
├── .kurali/
│   ├── manifest.json    # 包元数据
│   └── files.txt        # 文件清单
├── rootfs/              # 解压后的文件系统
└── scripts/             # 维护脚本（可选）
    ├── preinst
    └── postinst
```

### 安装 .kurali 包

```bash
kurali i myapp-1.0.kurali
```

---

## 15. 配置与环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `KURALI_HOME` | `/var/lib/kuraliAll` | 数据根目录 |
| `KURALI_MODULES_DIR` | 自动 | 模块搜索路径 |
| `KURALI_CONFIG_DIR` | 自动 | 配置文件路径 |

---

## 16. 故障排除

### "不支持的格式"
- 检查文件后缀是否正确
- 支持格式：`.deb` `.rpm` `.pkg.tar.*` `.pacman` `.apk` `.kurali` `AppImage` `.tar.*` `.zip`

### "解压失败"
- 检查文件是否损坏：`file <文件>`
- 确认工具可用：`dpkg-deb`（deb）、`rpm2cpio`（rpm）、`bsdtar`（多格式）

### "需要 root 权限"
```bash
sudo kurali i <文件>
```

### Permission denied
安装后 `kurali` 命令报错：
```bash
sudo chmod +x /var/lib/kuraliAll/kuraliAll.sh
```

### 程序运行报错
```bash
# 检查依赖
kurali deps <程序路径>

# 手动指定库路径
export LD_LIBRARY_PATH="/var/lib/kuraliAll/pkg/<包名>/rootfs/usr/lib:$LD_LIBRARY_PATH"
```

### 完全卸载 KuraliAll
```bash
sudo rm -rf /var/lib/kuraliAll
sudo rm -f /usr/local/bin/kurali
```

---

## 离线包获取方式

在有网的机器上下载软件包，U盘/SCP 传到目标机器：

```bash
# Debian/Ubuntu
apt download <包名>

# RHEL/CentOS
yumdownloader <包名>

# Arch
pacman -Sw <包名>

# 或从官网直接下载 .deb/.rpm/.AppImage 等
```
