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

# 修复 .desktop 文件中的 Exec 和 Icon 路径
_fix_desktop_paths() {
    local file="$1" extract_dir="$2"
    # 修复 Exec= 路径（绝对路径指向包内二进制）
    sed -i "s|^Exec=[^ ]*|Exec=${extract_dir}/usr/bin/|" "$file" 2>/dev/null || true
    # 更精确：找到原 Exec 值，替换成沙箱路径
    local orig_exec
    orig_exec=$(grep -m1 '^Exec=' "$file" | sed 's/^Exec=//' | awk '{print $1}')
    if [[ -n "$orig_exec" ]]; then
        local bn; bn=$(basename "$orig_exec")
        # 在包内找实际二进制
        local real_path
        real_path=$(find "$extract_dir/usr/bin" "$extract_dir/bin" "$extract_dir/usr/local/bin" -type f -executable -name "$bn" 2>/dev/null | head -1)
        if [[ -n "$real_path" ]]; then
            sed -i "s|^Exec=.*${bn}|Exec=${real_path}|" "$file" 2>/dev/null || true
        else
            # 找不到就直接用沙箱路径前缀
            sed -i "s|^Exec=${orig_exec}|Exec=${extract_dir}${orig_exec}|" "$file" 2>/dev/null || true
        fi
    fi

    # 修复 Icon= 路径（如果是相对名，在包内找对应图片）
    local orig_icon
    orig_icon=$(grep -m1 '^Icon=' "$file" | sed 's/^Icon=//')
    if [[ -n "$orig_icon" && "$orig_icon" != /* ]]; then
        # 在包内 icons 目录搜索
        local found_icon=""
        for ext in png svg xpm ico; do
            found_icon=$(find "$extract_dir/usr/share/icons" "$extract_dir/usr/share/pixmaps" \
                -name "${orig_icon}.${ext}" -type f 2>/dev/null | head -1)
            [[ -n "$found_icon" ]] && break
        done
        if [[ -n "$found_icon" ]]; then
            sed -i "s|^Icon=.*|Icon=${found_icon}|" "$file" 2>/dev/null || true
        fi
    fi
}

# 优先使用包内自带的 .desktop 文件，没有则自动生成
install_desktop_entry() {
    local name="$1" display="$2" exec_path="$3" icon="$4"
    local uh; uh=$(_user_home)
    local ddir="${uh}/.local/share/applications"
    mkdir -p "$ddir"

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

    if [[ -n "$icon" && -f "$icon" ]]; then
        local idir="${uh}/.local/share/icons/hicolor/256x256/apps"
        mkdir -p "$idir"
        local icon_dest="${idir}/kurali-${name}.png"
        cp "$icon" "$icon_dest" 2>/dev/null || true
        [[ -n "$SUDO_USER" ]] && chown "$SUDO_USER:" "$icon_dest" 2>/dev/null || true
        echo "Icon=${icon_dest}" >> "$df"
    fi

    [[ -n "$SUDO_USER" ]] && chown "$SUDO_USER:" "$df" 2>/dev/null || true
    _refresh_db
}

# 从包内复制 .desktop 文件并修复路径
install_desktop_from_pkg() {
    local pkg_desktop="$1" name="$2" extract_dir="$3"
    local uh; uh=$(_user_home)
    local ddir="${uh}/.local/share/applications"
    mkdir -p "$ddir"

    local df="${ddir}/kurali-${name}.desktop"
    cp "$pkg_desktop" "$df"

    _fix_desktop_paths "$df" "$extract_dir"

    # 如果 Icon= 是相对名且没被 _fix_desktop_paths 处理，复制图标文件
    local orig_icon
    orig_icon=$(grep -m1 '^Icon=' "$df" | sed 's/^Icon=//')
    if [[ -n "$orig_icon" && "$orig_icon" != /* ]]; then
        local found_icon=""
        for dir in "$extract_dir/usr/share/pixmaps" "$extract_dir/usr/share/icons"; do
            found_icon=$(find "$dir" -maxdepth 4 \( -name "${orig_icon}.png" -o -name "${orig_icon}.svg" -o -name "${orig_icon}.xpm" \) -type f 2>/dev/null | head -1)
            [[ -n "$found_icon" ]] && break
        done
        if [[ -n "$found_icon" ]]; then
            local idir="${uh}/.local/share/icons/hicolor/256x256/apps"
            mkdir -p "$idir"
            local icon_dest="${idir}/kurali-${name}.$(echo "$found_icon" | sed 's/.*\.//')"
            cp "$found_icon" "$icon_dest" 2>/dev/null || true
            [[ -n "$SUDO_USER" ]] && chown "$SUDO_USER:" "$icon_dest" 2>/dev/null || true
            sed -i "s|^Icon=.*|Icon=${icon_dest}|" "$df"
        fi
    fi

    [[ -n "$SUDO_USER" ]] && chown "$SUDO_USER:" "$df" 2>/dev/null || true
    _refresh_db
}

remove_desktop_entry() {
    local name="$1"
    local uh; uh=$(_user_home)
    rm -f "${uh}/.local/share/applications/kurali-${name}.desktop" 2>/dev/null
    rm -f "${uh}/.local/share/icons/hicolor/256x256/apps/kurali-${name}."* 2>/dev/null
    _refresh_db
    debug "桌面条目已移除: $name"
}

refresh_desktop() { _refresh_db; }

_refresh_db() {
    local uh; uh=$(_user_home)
    if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
        sudo -u "$SUDO_USER" update-desktop-database "${uh}/.local/share/applications" 2>/dev/null || true
        sudo -u "$SUDO_USER" xdg-desktop-menu forceupdate 2>/dev/null || true
    else
        update-desktop-database "${uh}/.local/share/applications" 2>/dev/null || true
        xdg-desktop-menu forceupdate 2>/dev/null || true
    fi
}
