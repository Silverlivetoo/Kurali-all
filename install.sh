#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════
#  KuraliAll 安装脚本
#  用法: sudo bash install.sh
# ═══════════════════════════════════════════════════════

set -uo pipefail

# ─── 颜色 ───
if [[ -t 1 ]]; then
    C_GREEN='\033[1;32m'; C_BLUE='\033[1;34m'
    C_RED='\033[1;31m';   C_YELLOW='\033[1;33m'
    C_RESET='\033[0m';    C_BOLD='\033[1m'
else
    C_GREEN=''; C_BLUE=''; C_RED=''; C_YELLOW=''; C_RESET=''; C_BOLD=''
fi

_info()  { printf "${C_BLUE}[INFO]${C_RESET}  %s\n" "$*"; }
_ok()    { printf "${C_GREEN}[ OK ]${C_RESET}  %s\n" "$*"; }
_err()   { printf "${C_RED}[ERR] ${C_RESET}  %s\n" "$*" >&2; }
_die()   { _err "$*"; exit 1; }

# ─── 权限检查 ───
if [[ "$EUID" -ne 0 ]]; then
    _info "自动提权..."
    exec sudo -- bash "$0" "$@"
fi

# ─── 路径 ───
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="/var/lib/kuraliAll"
BIN="/usr/local/bin/kurali"

# 从核心模块读取版本号
VERSION=$(grep '^KURALI_VERSION=' "${SRC_DIR}/modules/core.mod" 2>/dev/null \
    | head -1 | sed 's/.*"\(.*\)".*/\1/')
VERSION="${VERSION:-3.0.0}"

printf "\n${C_BOLD}KuraliAll v${VERSION}${C_RESET} — 安装到系统\n\n"

# ─── 安装文件 ───
_info "复制文件到 ${TARGET}..."
mkdir -p "${TARGET}"/{db,logs,pkg,backup,cache}
cp -a "${SRC_DIR}/modules" "${SRC_DIR}/config" "${SRC_DIR}/hooks" \
       "${SRC_DIR}/kuraliAll.sh" "${TARGET}/" \
    || _die "文件复制失败"
chmod +x "${TARGET}/kuraliAll.sh"

# ─── 写版本标记 ───
echo "$VERSION" > "${TARGET}/version"

# ─── 写入口包装脚本 ───
_info "创建命令 ${BIN}..."
cat > "$BIN" << 'WRAPPER'
#!/usr/bin/env bash
exec /var/lib/kuraliAll/kuraliAll.sh "$@"
WRAPPER
chmod +x "$BIN"

# ─── 完成 ───
printf "\n${C_GREEN}${C_BOLD}✓ 安装完成！${C_RESET}\n\n"
printf "  命令:  ${C_BLUE}%s${C_RESET}\n"   "$BIN"
printf "  数据:  ${C_BLUE}%s${C_RESET}\n"   "$TARGET"
printf "  帮助:  ${C_GREEN}kurali help${C_RESET}\n"
printf "  安装:  ${C_GREEN}sudo kurali i <文件>${C_RESET}\n"
printf "\n"
