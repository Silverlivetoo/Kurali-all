#!/usr/bin/env bash
# pre-install.mod — 安装前钩子
pre_install_hook() {
    local file="$1" dest="$2"
    debug "pre-install: $file → $dest"
    # 磁盘空间检查
    local avail; avail=$(df -k "$(dirname "$dest")" 2>/dev/null | awk 'NR==2{print $4}')
    if [[ -n "$avail" && "$avail" -lt 10240 ]]; then
        warn "磁盘空间不足 10MB (${avail}KB)"
    fi
    return 0
}
