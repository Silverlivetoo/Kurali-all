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

    # 先修复 bin 目录权限（dpkg-deb -x 可能丢失）
    for d in "$extract_dir/usr/bin" "$extract_dir/bin" "$extract_dir/usr/local/bin" "$extract_dir/usr/sbin" "$extract_dir/sbin"; do
        [[ -d "$d" ]] && chmod +x "$d"/* 2>/dev/null || true
    done

    # 先读取原始值（不要提前改文件！）
    local orig_exec orig_icon
    orig_exec=$(grep -m1 '^Exec=' "$file" | sed 's/^Exec=//' | awk '{print $1}')
    orig_icon=$(grep -m1 '^Icon=' "$file" | sed 's/^Icon=//')

    # 修复 Exec=
    if [[ -n "$orig_exec" ]]; then
        local bn; bn=$(basename "$orig_exec")
        # 在包内找实际二进制（先找可执行的，再找同名文件）
        local real_path
        real_path=$(find "$extract_dir/usr/bin" "$extract_dir/bin" "$extract_dir/usr/local/bin" "$extract_dir/usr/sbin" "$extract_dir/sbin" \
            -maxdepth 1 -type f -executable -name "$bn" 2>/dev/null | head -1)
        # 兜底：不限制 -executable
        [[ -z "$real_path" ]] && real_path=$(find "$extract_dir/usr/bin" "$extract_dir/bin" "$extract_dir/usr/local/bin" \
            -maxdepth 1 -type f -name "$bn" 2>/dev/null | head -1)
        if [[ -n "$real_path" ]]; then
            chmod +x "$real_path" 2>/dev/null || true
            sed -i "s|^Exec=.*${bn}|Exec=${real_path}|" "$file"
        elif [[ "$orig_exec" != /* ]]; then
            local search_path="${extract_dir}/usr/bin/${orig_exec}"
            [[ -f "$search_path" ]] && chmod +x "$search_path" 2>/dev/null || true
            sed -i "s|^Exec=${orig_exec}|Exec=${search_path}|" "$file"
        else
            local search_path="${extract_dir}${orig_exec}"
            [[ -f "$search_path" ]] && chmod +x "$search_path" 2>/dev/null || true
            sed -i "s|^Exec=${orig_exec}|Exec=${search_path}|" "$file"
        fi
    fi

    # 修复 Icon=（如果是相对名）
    if [[ -n "$orig_icon" && "$orig_icon" != /* ]]; then
        local found_icon=""
        for dir in "$extract_dir/usr/share/pixmaps" "$extract_dir/usr/share/icons"; do
            found_icon=$(find "$dir" -maxdepth 5 \( -name "${orig_icon}.png" -o -name "${orig_icon}.svg" -o -name "${orig_icon}.xpm" \) -type f 2>/dev/null | head -1)
            [[ -n "$found_icon" ]] && break
        done
        [[ -n "$found_icon" ]] && sed -i "s|^Icon=.*|Icon=${found_icon}|" "$file"
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
    ok "桌面条目: ${name}"
}

# 从包内复制 .desktop 文件并修复路径
install_desktop_from_pkg() {
    local pkg_desktop="$1" name="$2" extract_dir="$3"
    local uh; uh=$(_user_home)
    local ddir="${uh}/.local/share/applications"
    mkdir -p "$ddir"

    local df="${ddir}/kurali-${name}.desktop"
    cp "$pkg_desktop" "$df"

    # 读取修复前的 Icon 值
    local orig_icon
    orig_icon=$(grep -m1 '^Icon=' "$df" | sed 's/^Icon=//')

    # 修复 Exec 和 Icon 路径（指向沙箱目录）
    _fix_desktop_paths "$df" "$extract_dir"

    # 如果 Icon 是相对名，把图标复制到用户本地 share 并更新路径
    if [[ -n "$orig_icon" && "$orig_icon" != /* ]]; then
        local found_icon=""
        for dir in "$extract_dir/usr/share/pixmaps" "$extract_dir/usr/share/icons"; do
            found_icon=$(find "$dir" -maxdepth 5 \( -name "${orig_icon}.png" -o -name "${orig_icon}.svg" -o -name "${orig_icon}.xpm" \) -type f 2>/dev/null | head -1)
            [[ -n "$found_icon" ]] && break
        done
        if [[ -n "$found_icon" ]]; then
            local idir="${uh}/.local/share/icons/hicolor/256x256/apps"
            mkdir -p "$idir"
            local ext="${found_icon##*.}"
            local icon_dest="${idir}/kurali-${name}.${ext}"
            cp "$found_icon" "$icon_dest"
            [[ -n "$SUDO_USER" ]] && chown "$SUDO_USER:" "$icon_dest" 2>/dev/null || true
            sed -i "s|^Icon=.*|Icon=${icon_dest}|" "$df"
        fi
    fi

    [[ -n "$SUDO_USER" ]] && chown "$SUDO_USER:" "$df" 2>/dev/null || true
    _refresh_db
    ok "桌面条目: ${name}"
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
