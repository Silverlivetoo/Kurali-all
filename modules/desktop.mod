#!/usr/bin/env bash
# desktop.mod — 桌面集成

# 获取真实用户的 home（兼容 sudo 运行）
_user_home() {
    if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
        eval echo "~${SUDO_USER}"
    else
        echo "$HOME"
    fi
}

install_desktop_entry() {
    local name="$1" display="$2" exec_path="$3" icon="$4"
    local uh; uh=$(_user_home)
    local ddir="${uh}/.local/share/applications"
    local idir="${uh}/.local/share/icons/hicolor/256x256/apps"
    mkdir -p "$ddir" "$idir"

    local icon_dest=""
    if [[ -n "$icon" && -f "$icon" ]]; then
        icon_dest="${idir}/kurali-${name}.png"
        cp "$icon" "$icon_dest" 2>/dev/null || true
        # root 运行时修复权限
        [[ -n "$SUDO_USER" ]] && chown "$SUDO_USER:" "$icon_dest" 2>/dev/null || true
    fi

    local df="${ddir}/kurali-${name}.desktop"
    cat > "$df" << EOF
[Desktop Entry]
Name=${display}
Comment=KuraliAll: ${name}
Exec=${exec_path}
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
EOF

    if [[ -n "$icon_dest" && -f "$icon_dest" ]]; then
        echo "Icon=${icon_dest}" >> "$df"
    fi

    # root 运行时修复 .desktop 文件权限
    [[ -n "$SUDO_USER" ]] && chown "$SUDO_USER:" "$df" 2>/dev/null || true

    # 刷新真实用户的桌面数据库
    if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
        sudo -u "$SUDO_USER" update-desktop-database "$ddir" 2>/dev/null || true
    else
        update-desktop-database "$ddir" 2>/dev/null || true
    fi

    ok "桌面条目: ${name} → ${df}"
}

remove_desktop_entry() {
    local name="$1"
    local uh; uh=$(_user_home)
    local df="${uh}/.local/share/applications/kurali-${name}.desktop"
    rm -f "$df" 2>/dev/null
    rm -f "${uh}/.local/share/icons/hicolor/256x256/apps/kurali-${name}.png" 2>/dev/null
    if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
        sudo -u "$SUDO_USER" update-desktop-database "${uh}/.local/share/applications" 2>/dev/null || true
    else
        update-desktop-database "${uh}/.local/share/applications" 2>/dev/null || true
    fi
    debug "桌面条目已移除: $name"
}

refresh_desktop() {
    local uh; uh=$(_user_home)
    if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
        sudo -u "$SUDO_USER" update-desktop-database "${uh}/.local/share/applications" 2>/dev/null || true
        sudo -u "$SUDO_USER" xdg-desktop-menu forceupdate 2>/dev/null || true
    else
        update-desktop-database "${uh}/.local/share/applications" 2>/dev/null || true
        xdg-desktop-menu forceupdate 2>/dev/null || true
    fi
}
