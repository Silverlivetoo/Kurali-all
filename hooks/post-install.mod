#!/usr/bin/env bash
# post-install.mod — 安装后钩子
post_install_hook() {
    local file="$1" dest="$2" name="$3"
    debug "post-install: $name"
    # ldconfig
    has_cmd ldconfig && [[ -d "${dest}/usr/lib" ]] && ldconfig 2>/dev/null || true
    # mandb
    has_cmd mandb && [[ -d "${dest}/usr/share/man" ]] && mandb 2>/dev/null || true
    # 桌面
    has_cmd update-desktop-database && update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
    return 0
}
