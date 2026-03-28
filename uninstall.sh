#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════
#  KuraliAll 卸载脚本
#  用法: sudo bash uninstall.sh [--purge]
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
_warn()  { printf "${C_YELLOW}[WARN]${C_RESET}  %s\n" "$*" >&2; }
_err()   { printf "${C_RED}[ERR] ${C_RESET}  %s\n" "$*" >&2; }
_die()   { _err "$*"; exit 1; }

# ─── 参数解析 ───
PURGE=0
NO_CONFIRM=0
for arg in "$@"; do
    case "$arg" in
        --purge)       PURGE=1 ;;
        -y|--yes)      NO_CONFIRM=1 ;;
        -h|--help)
            echo -e "\n用法: sudo bash uninstall.sh [--purge] [-y]"
            echo ""
            echo "  --purge    同时删除已安装的软件包数据 (默认保留)"
            echo "  -y, --yes  跳过确认"
            echo ""
            exit 0
            ;;
        *)
            _die "未知参数: $arg (用 -h 查看帮助)"
            ;;
    esac
done

# ─── 权限检查 ───
[[ "$EUID" -eq 0 ]] || _die "请用 sudo 运行: sudo bash uninstall.sh"

# ─── 路径 ───
TARGET="/var/lib/kuraliAll"
BIN="/usr/local/bin/kurali"

# ─── 检查是否已安装 ───
if [[ ! -d "$TARGET" && ! -f "$BIN" ]]; then
    _warn "KuraliAll 似乎未安装 (未找到 ${TARGET} 或 ${BIN})"
    exit 0
fi

VERSION=""
[[ -f "${TARGET}/version" ]] && VERSION=$(cat "${TARGET}/version")
[[ -z "$VERSION" && -f "${TARGET}/modules/core.mod" ]] && \
    VERSION=$(grep '^readonly KURALI_VERSION=' "${TARGET}/modules/core.mod" 2>/dev/null \
    | head -1 | sed 's/.*"\(.*\)".*/\1/')
VERSION="${VERSION:-未知}"

# ─── 统计信息 ───
PKG_COUNT=0
PKG_SIZE=""
if [[ -d "${TARGET}/pkg" ]]; then
    PKG_COUNT=$(find "${TARGET}/pkg" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    PKG_SIZE=$(du -sh "${TARGET}/pkg" 2>/dev/null | cut -f1)
fi
TOTAL_SIZE=$(du -sh "$TARGET" 2>/dev/null | cut -f1)

printf "\n${C_BOLD}KuraliAll v${VERSION}${C_RESET} — 卸载\n\n"

# ─── 显示摘要 ───
echo -e "  ${C_CYAN}安装目录:${C_RESET}  ${TARGET}"
echo -e "  ${C_CYAN}入口命令:${C_RESET}  ${BIN}"
echo -e "  ${C_CYAN}总大小:${C_RESET}    ${TOTAL_SIZE:-未知}"
if [[ "$PKG_COUNT" -gt 0 ]]; then
    echo -e "  ${C_CYAN}已安装包:${C_RESET}  ${PKG_COUNT} 个 (${PKG_SIZE:-未知})"
    if [[ "$PURGE" -eq 0 ]]; then
        echo -e "  ${C_YELLOW}提示:${C_RESET}      使用 --purge 可同时删除已安装的软件包数据"
    else
        echo -e "  ${C_RED}⚠ 将删除所有已安装的软件包数据!${C_RESET}"
    fi
fi
echo ""

# ─── 确认 ───
if [[ "$NO_CONFIRM" -eq 0 ]]; then
    printf "${C_YELLOW}确认卸载 KuraliAll? [y/N]${C_RESET} "
    read -r answer
    case "$answer" in
        [yY][eE][sS]|[yY]) ;;
        *) _info "取消卸载"; exit 0 ;;
    esac
fi

# ─── 移除入口命令 ───
if [[ -f "$BIN" ]]; then
    _info "移除命令 ${BIN}..."
    rm -f "$BIN"
    _ok "已移除 ${BIN}"
fi

# ─── 移除桌面文件和图标 ───
_info "清理桌面集成文件..."
desktop_removed=0
for uh in /root /home/*; do
    [[ -d "$uh" ]] || continue
    # .desktop 文件
    local_desktop="${uh}/.local/share/applications"
    if [[ -d "$local_desktop" ]]; then
        while IFS= read -r df; do
            rm -f "$df"
            desktop_removed=$((desktop_removed+1))
        done < <(find "$local_desktop" -name "kurali-*.desktop" -type f 2>/dev/null)
    fi
    # 图标
    local_icons="${uh}/.local/share/icons/hicolor/256x256/apps"
    if [[ -d "$local_icons" ]]; then
        while IFS= read -r ic; do
            rm -f "$ic"
        done < <(find "$local_icons" -name "kurali-*" -type f 2>/dev/null)
    fi
done
[[ "$desktop_removed" -gt 0 ]] && _ok "已清理 ${desktop_removed} 个桌面文件"

# ─── 删除安装目录 ───
if [[ -d "$TARGET" ]]; then
    if [[ "$PURGE" -eq 1 ]]; then
        # Purge 模式：全部删除
        _info "删除安装目录 (purge 模式)..."
        rm -rf "$TARGET"
        _ok "已删除 ${TARGET}"
    else
        # 默认模式：保留用户数据 (pkg, db, logs, backup)，只移除程序文件
        _info "删除程序文件 (保留用户数据)..."
        rm -f "${TARGET}/kuraliAll.sh" "${TARGET}/version"
        rm -rf "${TARGET}/modules" "${TARGET}/config" "${TARGET}/hooks"
        rm -rf "${TARGET}/cache"
        _ok "已删除程序文件"

        # 报告保留的数据
        kept=0
        for d in pkg db logs backup; do
            [[ -d "${TARGET}/${d}" ]] && kept=$((kept+1))
        done
        if [[ "$kept" -gt 0 ]]; then
            echo ""
            _info "以下数据已保留在 ${TARGET}:"
            for d in pkg db logs backup; do
                [[ -d "${TARGET}/${d}" ]] && echo -e "  ${C_CYAN}→${C_RESET} ${TARGET}/${d}"
            done
            echo ""
            _info "如需完全删除: sudo bash uninstall.sh --purge"
        else
            rm -rf "$TARGET"
            _ok "无保留数据，已删除 ${TARGET}"
        fi
    fi
fi

# ─── 完成 ───
printf "\n${C_GREEN}${C_BOLD}✓ 卸载完成！${C_RESET}\n\n"
