#!/usr/bin/env bash
# system.mod — 发行版检测、原生包管理器

DISTRO_ID="" DISTRO_NAME="" DISTRO_MGR="" DISTRO_INSTALL="" DISTRO_REMOVE="" DISTRO_QUERY=""

detect_distro() {
    if [[ -n "$USER_DISTRO" ]]; then
        _load_distro "$USER_DISTRO" && { info "指定发行版: ${DISTRO_NAME}"; return 0; }
        die "未知发行版: $USER_DISTRO"
    fi
    if [[ -f /etc/os-release ]]; then
        local id; id=$(. /etc/os-release && echo "$ID"); id="${id,,}"
        if _load_distro "$id"; then info "检测: ${DISTRO_NAME} (${DISTRO_ID})"; return 0; fi
    fi
    [[ -f /etc/debian_version ]] && { _load_distro "debian" && return 0; }
    [[ -f /etc/redhat-release ]] && { _load_distro "rhel" && return 0; }
    [[ -f /etc/arch-release ]] && { _load_distro "arch" && return 0; }
    [[ -f /etc/alpine-release ]] && { _load_distro "alpine" && return 0; }
    has_cmd lsb_release && { _load_distro "$(lsb_release -si | tr '[:upper:]' '[:lower:]')" && return 0; }
    warn "无法检测发行版，请用 --distro=<id>"
    return 1
}

_load_distro() {
    local id="$1" db="${KURALI_CONFIG_DIR:-${KURALI_HOME}/config}/distros.txt"
    [[ -f "$db" ]] || return 1
    local line; line=$(grep -i "^${id}|" "$db" | head -1)
    [[ -z "$line" ]] && return 1
    IFS='|' read -r DISTRO_ID DISTRO_NAME DISTRO_MGR DISTRO_INSTALL DISTRO_REMOVE DISTRO_QUERY <<< "$line"
    # has_cmd 可能未定义（独立 source 时），用 command -v 兜心
    if declare -F has_cmd >/dev/null 2>&1; then
        has_cmd "$DISTRO_MGR" || { warn "$DISTRO_MGR 不可用"; return 1; }
    else
        command -v "$DISTRO_MGR" >/dev/null 2>&1 || { echo "[WARN] $DISTRO_MGR 不可用" >&2; return 1; }
    fi
    return 0
}

select_distro() {
    local db="${KURALI_CONFIG_DIR:-${KURALI_HOME}/config}/distros.txt"
    [[ -f "$db" ]] || die "发行版数据库缺失"
    echo -e "${C_BOLD}选择发行版:${C_RESET}" >&2
    local -a ids=(); local idx=0
    while IFS='|' read -r id name _rest; do
        idx=$((idx+1)); ids+=("$id")
        printf "  ${C_CYAN}%2d${C_RESET}) %-15s %s\n" "$idx" "$id" "$name" >&2
    done < "$db"
    read -rp "$(echo -e "${C_YELLOW}[?]${C_RESET} 编号 [1-${idx}]: ")" ch
    [[ "$ch" -ge 1 && "$ch" -le "$idx" ]] || die "无效选择"
    _load_distro "${ids[$((ch-1))]}"
    info "已选择: ${DISTRO_NAME}"
}

native_install() {
    local pkg="$1"; [[ -z "$pkg" ]] && die "用法: kurali native <包名>"
    detect_distro 2>/dev/null || true
    info "通过 ${DISTRO_MGR:-系统} 安装: ${pkg}"
    eval "$DISTRO_INSTALL $pkg"
}

