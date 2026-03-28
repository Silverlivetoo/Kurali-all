#!/usr/bin/env bash
# desktop.mod — 桌面集成

install_desktop_entry() {
    local name="$1" display="$2" exec_path="$3" icon="$4"
    local ddir="${HOME}/.local/share/applications"
    local idir="${HOME}/.local/share/icons/hicolor/256x256/apps"
    mkdir -p "$ddir" "$idir"

    local icon_dest=""
    # 如果有图标文件则复制，否则使用系统默认图标
    if [[ -n "$icon" && -f "$icon" ]]; then
        icon_dest="${idir}/kurali-${name}.png"
        cp "$icon" "$icon_dest" 2>/dev/null || true
    fi

    local df="${ddir}/kurali-${name}.desktop"
    cat > "$df" << EOF
[Desktop Entry]
Name=${display}
Comment=Installed via KuraliAll: ${name}
Exec=${exec_path}
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
EOF
    # 如果有图标则指定图标路径，否则让系统使用默认图标
    if [[ -n "$icon_dest" && -f "$icon_dest" ]]; then
        echo "Icon=${icon_dest}" >> "$df"
    else
        # 使用通用图标或空（使用系统默认）
        echo "Icon=application-x-executable" >> "$df"
    fi

    # 刷新桌面数据库（多个方法）
    has_cmd update-desktop-database && update-desktop-database "$ddir" 2>/dev/null || true
    has_cmd xdg-desktop-menu && xdg-desktop-menu install "$df" 2>/dev/null || true

    ok "桌面条目: ${name}"
}

remove_desktop_entry() {
    local name="$1"
    local df="${HOME}/.local/share/applications/kurali-${name}.desktop"
    rm -f "$df" 2>/dev/null
    rm -f "${HOME}/.local/share/icons/hicolor/256x256/apps/kurali-${name}.png" 2>/dev/null
    has_cmd update-desktop-database && update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
    has_cmd xdg-desktop-menu && xdg-desktop-menu uninstall "$df" 2>/dev/null || true
    debug "桌面条目已移除: $name"
}

refresh_desktop() {
    has_cmd update-desktop-database && update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
    has_cmd gtk-update-icon-cache && gtk-update-icon-cache -f "${HOME}/.local/share/icons/hicolor" 2>/dev/null || true
    has_cmd xdg-desktop-menu && xdg-desktop-menu forceupdate 2>/dev/null || true
}
