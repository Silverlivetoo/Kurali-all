#!/usr/bin/env bash
# post-install.mod — 安装后钩子
post_install_hook() {
    local file="$1" dest="$2" name="$3"
    debug "post-install: $name"
    # ldconfig
    has_cmd ldconfig && [[ -d "${dest}/usr/lib" ]] && ldconfig 2>/dev/null || true
    # mandb
    has_cmd mandb && [[ -d "${dest}/usr/share/man" ]] && mandb 2>/dev/null || true
    # 桌面数据库（获取真实用户 home，兼容 sudo）
    if has_cmd update-desktop-database; then
        local uh="${HOME:-/root}"
        if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
            uh=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
            [[ -z "$uh" ]] && uh="${HOME:-/root}"
        fi
        update-desktop-database "${uh}/.local/share/applications" 2>/dev/null || true
    fi
    return 0
}
