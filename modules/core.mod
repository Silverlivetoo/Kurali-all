#!/usr/bin/env bash
# core.mod — 核心：常量、日志、模块加载器
# KuraliAll v2.1

KURALI_VERSION="2.2.0"
KURALI_NAME="KuraliAll"

# ─── 颜色 ───
C_RESET='\033[0m'
C_RED='\033[1;31m'
C_GREEN='\033[1;32m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_CYAN='\033[1;36m'
C_BOLD='\033[1m'
C_GRAY='\033[0;90m'

# ─── 全局路径 ───
KURALI_HOME="${KURALI_HOME:-/var/lib/kuraliAll}"
KURALI_BIN="${KURALI_BIN:-/usr/local/bin/kurali}"
DB_DIR="${KURALI_HOME}/db"
LOG_DIR="${KURALI_HOME}/logs"
PKG_DIR="${KURALI_HOME}/pkg"
BACKUP_DIR="${KURALI_HOME}/backup"
CACHE_DIR="${KURALI_HOME}/cache"

# ─── 全局标志 ───
MODE_RAM=0
MODE_DOCKER=0
MODE_SYSTEM=0       # 1=直接安装到系统路径
MODE_BACKUP=1       # 1=安装前自动备份
VERBOSE=0
QUIET=0
NO_CONFIRM=0
USER_DISTRO=""
SAFE_MODE=0         # 安全模式，需额外确认危险操作

# ─── 日志 ───
_log() {
    local level="$1" color="$2"; shift 2
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    if [[ -d "$LOG_DIR" ]]; then
        echo "[$ts] [$level] $msg" >> "$LOG_DIR/kuraliAll.log" 2>/dev/null || true
    fi
    [[ "$QUIET" -eq 0 ]] && echo -e "${color}[$level]${C_RESET} $msg" >&2
}
info()  { _log "INFO"  "$C_BLUE"   "$*"; }
ok()    { _log "OK"    "$C_GREEN"  "$*"; }
warn()  { _log "WARN"  "$C_YELLOW" "$*"; }
err()   { _log "ERROR" "$C_RED"    "$*"; }
debug() { [[ "$VERBOSE" -eq 1 ]] && _log "DEBUG" "$C_CYAN" "$*"; }
die()   { err "$*"; exit 1; }

# ─── 确认 ───
confirm() {
    local prompt="$1"
    [[ "$NO_CONFIRM" -eq 1 ]] && return 0
    read -rp "$(echo -e "${C_YELLOW}[?]${C_RESET} $prompt [y/N] ")" ans
    [[ "$ans" == "y" || "$ans" == "Y" ]]
}

danger_confirm() {
    local prompt="$1"
    echo -e "${C_RED}${C_BOLD}⚠ 危险操作${C_RESET}"
    echo -e "${C_YELLOW}  $prompt${C_RESET}"
    [[ "$NO_CONFIRM" -eq 1 ]] && return 0
    read -rp "$(echo -e "${C_RED}  请输入 'yes' 确认: ")" ans
    [[ "$ans" == "yes" ]]
}

# ─── 离线检测 ───
check_offline() {
    if curl -s --connect-timeout 2 -o /dev/null "http://connectivity-check.ubuntu.com" 2>/dev/null ||
       ping -c1 -W2 8.8.8.8 &>/dev/null 2>&1; then
        debug "网络连接可用"
        return 0
    else
        debug "离线环境"
        return 1
    fi
}

# ─── 工具检查 ───
has_cmd() { command -v "$1" &>/dev/null; }

ensure_tools() {
    local missing=()
    for tool in "$@"; do
        has_cmd "$tool" || missing+=("$tool")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "缺少工具: ${missing[*]}"
        return 1
    fi
    return 0
}

# ─── 权限 ───
need_root() {
    if [[ "$EUID" -ne 0 ]]; then
        die "需要 root 权限 (sudo kuraliAll ...)"
    fi
}

safe_sudo() {
    if [[ "$EUID" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

# ─── 安全复制（带备份）───
safe_copy() {
    local src="$1" dst="$2"
    local real_dst="$dst"
    # 确保路径以 / 开头
    [[ "$real_dst" != /* ]] && real_dst="/$real_dst"

    # 备份已存在的文件
    if [[ "$MODE_BACKUP" -eq 1 && -e "$real_dst" ]]; then
        local bak="${BACKUP_DIR}${real_dst}.$(date +%s).bak"
        mkdir -p "$(dirname "$bak")" 2>/dev/null || safe_sudo mkdir -p "$(dirname "$bak")"
        safe_sudo cp -a "$real_dst" "$bak" 2>/dev/null || true
        debug "备份: $real_dst → $bak"
    fi

    # 复制
    safe_sudo mkdir -p "$(dirname "$real_dst")" 2>/dev/null || true
    if [[ -d "$src" ]]; then
        [[ -d "$real_dst" ]] || safe_sudo mkdir -p "$real_dst" 2>/dev/null || true
        safe_sudo cp -a "$src"/* "$real_dst/" 2>/dev/null || safe_sudo cp -a "$src" "$real_dst/" 2>/dev/null || true
    else
        safe_sudo cp -a "$src" "$real_dst" 2>/dev/null || true
    fi
}

# ─── 模块加载器 ───
declare -a _loaded=()

load_module() {
    local mod="$1"
    for m in "${_loaded[@]}"; do [[ "$m" == "$mod" ]] && return 0; done
    local found=""
    for dir in "${KURALI_MODULES_DIR}" "${KURALI_HOME}/modules" "$(dirname "${BASH_SOURCE[0]}")"; do
        [[ -z "$dir" ]] && continue
        [[ -f "${dir}/${mod}.mod" ]] && { found="${dir}/${mod}.mod"; break; }
    done
    [[ -z "$found" ]] && { warn "模块缺失: ${mod}.mod"; return 1; }
    source "$found"
    _loaded+=("$mod")
    debug "加载模块: $mod"
    return 0
}

# ─── 初始化目录 ───
init_dirs() {
    mkdir -p "$DB_DIR" "$LOG_DIR" "$PKG_DIR" "$BACKUP_DIR" "$CACHE_DIR" 2>/dev/null || true
    touch "$LOG_DIR/kuraliAll.log" 2>/dev/null || true
}

# ─── 帮助 ───
show_help() {
    cat << 'EOF'
KuraliAll v2.1 — 全能Linux包管理器

用法:  kurali <命令> [选项] [参数]

安装:  sudo bash install.sh    (安装到系统后用 kurali 命令)

命令:
  i  <文件>        安装软件包 (.deb/.rpm/pacman/.apk/AppImage/tar/zip)
  r  <包名>        卸载已安装的包
  l                 列出已安装的包
  s  <关键词>       搜索已安装的包
  f  <包名>         查看包详情
  run <文件>        内存模式运行（不安装，退出即清理）
  pack <文件> [输出] 把任意格式打包成 .kurali 格式
  native <包名>     用系统原生包管理器安装
  deps [文件]       检查系统/程序依赖
  boot enable|disable <服务>  服务自启管理
  docker <包名>     转容器模式
  update            检查版本更新
  help              显示帮助

选项:
  --ram             内存模式
  --docker          失败时容器兜底
  --system          直接安装到系统路径 (⚠ 危险)
  --no-backup       不备份被覆盖的文件
  --distro=<id>     指定发行版
  --select-distro   交互选择发行版
  -y                自动确认
  -v                详细输出
  -q                静默模式
  --install-self    安装 KuraliAll 到系统

支持: .deb  .rpm  .pkg.tar.*  .pacman  .apk  AppImage  .tar.*  .zip
发行版: Debian/Ubuntu/RHEL/CentOS/Fedora/Arch/Alpine/openSUSE 等 20+

离线支持: 完全离线工作，无需联网
EOF
}
