#!/usr/bin/env bash
# core.mod — 核心：常量、日志、模块加载器
# KuraliAll v3.0 — 纯 Shell 重构

KURALI_VERSION="3.0.0"
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
LOG_DIR="${KURALI_HOME}/logs"
PKG_DIR="${KURALI_HOME}/pkg"
BACKUP_DIR="${KURALI_HOME}/backup"
CACHE_DIR="${KURALI_HOME}/cache"

# ─── 全局标志 ───
MODE_RAM=0
MODE_DOCKER=0
MODE_SYSTEM=0
MODE_BACKUP=1
VERBOSE=0
QUIET=0
NO_CONFIRM=0
USER_DISTRO=""

# ─── 日志 ───
_log() {
    local level="$1" color="$2"; shift 2
    local msg="$*"
    local ts; ts="$(date '+%Y-%m-%d %H:%M:%S')"
    [[ -d "$LOG_DIR" ]] && echo "[$ts] [$level] $msg" >> "$LOG_DIR/kuraliAll.log" 2>/dev/null || true
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
    [[ "$NO_CONFIRM" -eq 1 ]] && return 0
    read -rp "$(echo -e "${C_YELLOW}[?]${C_RESET} $1 [y/N] ")" ans
    [[ "$ans" == "y" || "$ans" == "Y" ]]
}

danger_confirm() {
    echo -e "${C_RED}${C_BOLD}⚠ 危险操作${C_RESET}"
    echo -e "${C_YELLOW}  $1${C_RESET}"
    [[ "$NO_CONFIRM" -eq 1 ]] && return 0
    read -rp "$(echo -e "${C_RED}  请输入 'yes' 确认: ${C_RESET}")" ans
    [[ "$ans" == "yes" ]]
}

# ─── 工具检查 ───
has_cmd() { command -v "$1" &>/dev/null; }

# ─── 权限 ───
need_root() {
    [[ "$EUID" -ne 0 ]] && die "需要 root 权限 (sudo kuraliAll ...)"
}

# ─── 解压后修复文件权限（dpkg-deb -x 可能丢失执行权限）───
_fix_perms() {
    local dir="$1"
    # 标准路径
    for d in "$dir/usr/bin" "$dir/bin" "$dir/usr/local/bin" "$dir/usr/sbin" "$dir/sbin"; do
        [[ -d "$d" ]] && chmod +x "$d"/* 2>/dev/null || true
    done
    # /opt 等非标准路径
    find "$dir/opt" -type d -name bin 2>/dev/null | while IFS= read -r d; do
        chmod +x "$d"/* 2>/dev/null || true
    done
    # 恢复 ELF 和脚本的执行权限（全目录扫描）
    find "$dir" -type f 2>/dev/null | while IFS= read -r f; do
        local head_bytes
        head_bytes=$(xxd -l 4 -p "$f" 2>/dev/null)
        if [[ "$head_bytes" == "7f454c46" ]]; then
            # ELF 二进制
            chmod +x "$f" 2>/dev/null || true
        elif head -1 "$f" 2>/dev/null | grep -q '^#!'; then
            # 脚本（有 shebang）
            chmod +x "$f" 2>/dev/null || true
        fi
    done
}

safe_sudo() {
    [[ "$EUID" -eq 0 ]] && "$@" || sudo "$@"
}

# ─── 安全复制（带备份）───
safe_copy() {
    local src="$1" dst="$2"
    [[ "$dst" != /* ]] && dst="/$dst"

    if [[ "$MODE_BACKUP" -eq 1 && -e "$dst" ]]; then
        local bak="${BACKUP_DIR}${dst}.$(date +%s).bak"
        safe_sudo mkdir -p "$(dirname "$bak")" 2>/dev/null || true
        safe_sudo cp -a "$dst" "$bak" 2>/dev/null || true
        debug "备份: $dst → $bak"
    fi

    safe_sudo mkdir -p "$(dirname "$dst")" 2>/dev/null || true
    if [[ -d "$src" ]]; then
        [[ -d "$dst" ]] || safe_sudo mkdir -p "$dst" 2>/dev/null || true
        safe_sudo cp -a "$src"/* "$dst/" 2>/dev/null || safe_sudo cp -a "$src" "$dst/" 2>/dev/null || true
    else
        safe_sudo cp -a "$src" "$dst" 2>/dev/null || true
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
    mkdir -p "$LOG_DIR" "$PKG_DIR" "$BACKUP_DIR" "$CACHE_DIR" 2>/dev/null || true
    touch "$LOG_DIR/kuraliAll.log" 2>/dev/null || true
}

# ─── 帮助 ───
show_help() {
    cat << 'EOF'
KuraliAll v3.0.0 — 全能Linux包管理器 (纯Shell版)

用法:  kurali <命令> [选项] [参数]

安装:  sudo bash kuraliAll.sh --install-self    (安装到系统后用 kurali 命令)

命令:
  i  <文件>         安装软件包 (.deb/.rpm/pacman/.apk/AppImage/tar/zip)
  r  <包名>         卸载已安装的包
  l                  列出已安装的包
  s  <关键词>        搜索已安装的包
  f  <包名>          查看包详情
  run <文件>         内存模式运行（不安装，退出即清理）
  pack <文件> [输出]  把任意格式打包成 .kurali 格式
  native <包名>      用系统原生包管理器安装
  deps [文件]        检查系统/程序依赖
  boot enable|disable|status <服务>  服务自启管理
  update             版本信息
  self-update        联网检查并更新 KuraliAll
  network status|grant|revoke  联网许可管理
  help               显示帮助

选项:
  --ram             内存模式
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

⚠ .apk = Alpine Linux 包格式，不是安卓 APK
纯 Shell 实现，零外部依赖（Python/Node/...）
EOF
}
