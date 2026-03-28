#!/usr/bin/env bash
# pkg-handler.mod — 统一包格式处理（纯 Shell，零 Python 依赖）
# 支持: deb / rpm / pacman / apk / appimage / tar / zip / kurali

# ═══════════════════════════════════════════════════════
#  格式检测
# ═══════════════════════════════════════════════════════

detect_format() {
    local f="$1"
    case "$f" in
        *.deb)               echo "deb"     ; return ;;
        *.rpm)               echo "rpm"     ; return ;;
        *.pacman)            echo "pacman"  ; return ;;
        *.pkg.tar*)          echo "pacman"  ; return ;;
        *.kurali)            echo "kurali"  ; return ;;
        *.[Aa]pp[Ii]mage)   echo "appimage"; return ;;
        *.apk)               echo "apk"     ; return ;;
        *.tar.*|*.tgz|*.txz) echo "tar"    ; return ;;
        *.zip)               echo "zip"     ; return ;;
        *)                   echo "unknown" ;;
    esac
}

# ═══════════════════════════════════════════════════════
#  包信息提取
# ═══════════════════════════════════════════════════════

get_pkg_name() {
    local file="$1" format="$2" name=""
    case "$format" in
        deb)
            if has_cmd dpkg-deb; then
                name=$(dpkg-deb -f "$file" Package 2>/dev/null)
            elif has_cmd ar; then
                local tmp; tmp=$(mktemp -d)
                (cd "$tmp" && ar x "$file" control.tar.gz control.tar.xz control.tar.zst control.tar 2>/dev/null)
                for ct in control.tar.xz control.tar.zst control.tar.gz control.tar; do
                    [[ -f "$tmp/$ct" ]] && {
                        tar xf "$tmp/$ct" -C "$tmp" ./control 2>/dev/null
                        name=$(grep -i '^Package:' "$tmp/control" 2>/dev/null | head -1 | sed 's/^Package:[[:space:]]*//i')
                        break
                    }
                done
                rm -rf "$tmp"
            fi
            [[ -z "$name" ]] && name=$(basename "$file" .deb)
            ;;
        rpm)
            if has_cmd rpm; then
                name=$(rpm -qp --qf "%{NAME}" "$file" 2>/dev/null)
            fi
            [[ -z "$name" ]] && name=$(basename "$file" .rpm)
            ;;
        pacman)
            if has_cmd bsdtar; then
                name=$(bsdtar xf "$file" -O .PKGINFO 2>/dev/null | grep -E "^pkgname[[:space:]]*=" | head -1 | sed 's/^pkgname[[:space:]]*=[[:space:]]*//')
            fi
            [[ -z "$name" ]] && name=$(basename "$file" | sed 's/\.pkg\.tar.*//')
            ;;
        kurali)
            local tmp; tmp=$(mktemp -d)
            tar xzf "$file" -C "$tmp" .kurali/manifest.json 2>/dev/null
            name=$(grep '"name"' "$tmp/.kurali/manifest.json" 2>/dev/null | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"//;s/".*//')
            rm -rf "$tmp"
            ;;
        apk)
            local tmp; tmp=$(mktemp -d)
            tar xzf "$file" -C "$tmp" .PKGINFO 2>/dev/null
            name=$(grep -E "^origin[[:space:]]*=" "$tmp/.PKGINFO" 2>/dev/null | head -1 | sed 's/^origin[[:space:]]*=[[:space:]]*//')
            [[ -z "$name" ]] && name=$(grep -E "^pkgname[[:space:]]*=" "$tmp/.PKGINFO" 2>/dev/null | head -1 | sed 's/^pkgname[[:space:]]*=[[:space:]]*//')
            rm -rf "$tmp"
            [[ -z "$name" ]] && name=$(basename "$file" .apk)
            ;;
        appimage)
            # 尝试从文件名推断包名，去掉版本号和架构
            local bn; bn=$(basename "$file" | sed 's/\.[Aa]pp[Ii]mage$//')
            # 去掉常见后缀: _x86_64, -linux, -amd64 等
            bn=$(echo "$bn" | sed -E 's/[-_](x86_64|aarch64|arm64|amd64|i[3-6]86|linux|Linux)$//')
            name="${bn,,}"
            ;;
        tar|zip)
            name=$(basename "$file" | sed -E 's/\.(tar\.(gz|xz|bz2|zst)|tgz|zip)$//'); name="${name,,}"
            ;;
    esac
    echo "${name:-unknown}"
}

get_pkg_version() {
    local file="$1" format="$2"
    case "$format" in
        deb)     has_cmd dpkg-deb && dpkg-deb -f "$file" Version 2>/dev/null ;;
        rpm)     has_cmd rpm && rpm -qp --qf "%{VERSION}" "$file" 2>/dev/null ;;
        pacman)  has_cmd bsdtar && bsdtar xf "$file" -O .PKGINFO 2>/dev/null | grep -E "^pkgver[[:space:]]*=" | head -1 | sed 's/^pkgver[[:space:]]*=[[:space:]]*//' ;;
        kurali)
            local tmp; tmp=$(mktemp -d)
            tar xzf "$file" -C "$tmp" .kurali/manifest.json 2>/dev/null
            grep '"version"' "$tmp/.kurali/manifest.json" 2>/dev/null | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"//;s/".*//'
            rm -rf "$tmp"
            ;;
        apk)
            local tmp; tmp=$(mktemp -d)
            tar xzf "$file" -C "$tmp" .PKGINFO 2>/dev/null
            grep -E "^pkgver[[:space:]]*=" "$tmp/.PKGINFO" 2>/dev/null | head -1 | sed 's/^pkgver[[:space:]]*=[[:space:]]*//'
            rm -rf "$tmp"
            ;;
        *)  echo "unknown" ;;
    esac
}

# ═══════════════════════════════════════════════════════
#  RPM 纯 Shell 解压（无需 rpm2cpio / python3）
# ═══════════════════════════════════════════════════════

# 扫描 RPM 文件中的 cpio magic 并提取
_extract_rpm_pure() {
    local rpm_file="$1" dest="$2"
    debug "纯 shell RPM 解压"

    local tmp; tmp=$(mktemp -d)
    local payload="${tmp}/payload"

    # 方法1: 扫描 cpio magic (070707 或 070701)
    local offset
    offset=$(LANG=C grep -aob '070707\|070701\|070702' "$rpm_file" 2>/dev/null | head -1 | cut -d: -f1)

    if [[ -n "$offset" && "$offset" -gt 0 ]]; then
        dd if="$rpm_file" bs=1 skip="$offset" 2>/dev/null > "$payload"
    else
        # 方法2: RPM lead = 96 字节，手动跳过 signature header + main header
        # RPM header 结构: magic(4) + reserved(4) + il(4) + dl(4) = 16 字节头, 然后 il*16 条目, 然后 dl 数据
        # 用 xxd 提取字节做二进制解析
        local filesize; filesize=$(stat -c%s "$rpm_file" 2>/dev/null || stat -f%z "$rpm_file" 2>/dev/null)
        local pos=96

        for _ in 1 2; do
            [[ $((pos + 16)) -gt "$filesize" ]] && break
            # 检查 header magic: 8e ad e8 01
            local hdr_magic
            hdr_magic=$(xxd -s "$pos" -l 4 -p "$rpm_file" 2>/dev/null)
            [[ "$hdr_magic" != "8eade801" ]] && break

            # 读取 index count (big-endian, bytes 8-11) 和 data length (bytes 12-15)
            local il_hex dl_hex
            il_hex=$(xxd -s $((pos + 8)) -l 4 -p "$rpm_file" 2>/dev/null)
            dl_hex=$(xxd -s $((pos + 12)) -l 4 -p "$rpm_file" 2>/dev/null)

            local il dl
            il=$((16#$il_hex))
            dl=$((16#$dl_hex))

            local hdr_size=$((16 + il * 16 + dl))
            # 对齐到 8 字节边界
            if (( hdr_size % 8 != 0 )); then
                hdr_size=$((hdr_size + 8 - hdr_size % 8))
            fi
            pos=$((pos + hdr_size))
        done

        # 剩余数据就是 cpio payload
        if [[ $pos -lt "$filesize" ]]; then
            dd if="$rpm_file" bs=1 skip="$pos" 2>/dev/null > "$payload"
        fi
    fi

    # 检测 payload 压缩格式并解压
    local cpio_file="${tmp}/decompressed.cpio"
    if [[ -s "$payload" ]]; then
        local magic
        magic=$(xxd -l 6 -p "$payload" 2>/dev/null)

        case "$magic" in
            1f8b*)
                has_cmd gzip && gzip -dc "$payload" > "$cpio_file" 2>/dev/null
                ;;
            fd377a*)
                has_cmd xz && xz -dc "$payload" > "$cpio_file" 2>/dev/null
                ;;
            425a68*)
                has_cmd bunzip2 && bunzip2 -dc "$payload" > "$cpio_file" 2>/dev/null
                ;;
            28b52ffd*)
                has_cmd zstd && zstd -dc "$payload" > "$cpio_file" 2>/dev/null
                ;;
            *)
                cp "$payload" "$cpio_file"
                ;;
        esac
    fi

    # 解压 cpio
    if [[ -s "$cpio_file" ]]; then
        if has_cmd cpio; then
            (cd "$dest" && cpio -idm --quiet < "$cpio_file" 2>/dev/null) || \
            (cd "$dest" && cpio -idm < "$cpio_file" 2>/dev/null)
        else
            rm -rf "$tmp"
            err "需要 cpio 命令来解压 RPM 包"
            return 1
        fi
    fi

    rm -rf "$tmp"
    local count; count=$(find "$dest" -type f 2>/dev/null | wc -l)
    [[ $count -gt 0 ]]
}

# ═══════════════════════════════════════════════════════
#  提取：统一入口
# ═══════════════════════════════════════════════════════

extract_pkg() {
    local file="$1" format="$2" dest="$3"
    info "解压: $(basename "$file") [$format]"

    case "$format" in
        deb)
            if has_cmd dpkg-deb; then
                dpkg-deb -x "$file" "$dest" 2>/dev/null
            elif has_cmd ar; then
                local tmp; tmp=$(mktemp -d)
                (cd "$tmp" && ar x "$file")
                for dt in data.tar.xz data.tar.zst data.tar.gz data.tar.bz2 data.tar; do
                    [[ -f "$tmp/$dt" ]] && { tar xf "$tmp/$dt" -C "$dest"; break; }
                done
                rm -rf "$tmp"
            else
                err "需要 dpkg-deb 或 ar 来处理 .deb 包"
                return 1
            fi
            ;;

        rpm)
            if has_cmd rpm2cpio; then
                (cd "$dest" && rpm2cpio "$file" | cpio -idm --quiet 2>/dev/null)
            elif has_cmd bsdtar; then
                bsdtar xf "$file" -C "$dest"
            else
                _extract_rpm_pure "$file" "$dest" || {
                    err "RPM 解压失败（需要 rpm2cpio/bsdtar/cpio 其中之一）"
                    return 1
                }
            fi
            ;;

        pacman)
            local ext="${file##*.}"
            if [[ "$ext" == "zst" ]]; then
                if has_cmd zstd; then
                    zstd -d "$file" -c | tar xf - -C "$dest"
                elif has_cmd bsdtar; then
                    bsdtar xf "$file" -C "$dest"
                else
                    err "需要 zstd 或 bsdtar 解压 .pkg.tar.zst"
                    return 1
                fi
            elif has_cmd bsdtar; then
                bsdtar xf "$file" -C "$dest"
            else
                tar xf "$file" -C "$dest"
            fi
            rm -f "$dest/.PKGINFO" "$dest/.MTREE" "$dest/.INSTALL" "$dest/.BUILDINFO" 2>/dev/null
            ;;

        appimage)
            cp "$file" "$dest/"
            chmod +x "$dest/$(basename "$file")"
            local extracted=0

            # 方法1: --appimage-extract
            (cd "$dest" && "./$(basename "$file")" --appimage-extract > /dev/null 2>&1) && \
            { rm "$dest/$(basename "$file")"; extracted=1; }

            # 方法2: unsquashfs（SquashFS 类型）
            if [[ $extracted -eq 0 ]] && has_cmd unsquashfs; then
                local offset
                offset=$(LANG=C grep -aob 'hsqs' "$file" 2>/dev/null | head -1 | cut -d: -f1)
                if [[ -n "$offset" ]]; then
                    rm "$dest/$(basename "$file")"
                    dd if="$file" bs=1 skip="$offset" 2>/dev/null | unsquashfs -d "$dest/squashfs-root" - > /dev/null 2>&1 && \
                    { mv "$dest/squashfs-root"/* "$dest/" 2>/dev/null; rm -rf "$dest/squashfs-root"; extracted=1; }
                fi
            fi

            [[ $extracted -eq 0 ]] && warn "AppImage 提取失败，保留原始文件"
            ;;

        tar)
            local ext="${file##*.}"
            case "$ext" in
                gz|tgz) tar xzf "$file" -C "$dest" ;;
                xz)     tar xJf "$file" -C "$dest" ;;
                bz2)    tar xjf "$file" -C "$dest" ;;
                zst)
                    if has_cmd zstd; then
                        zstd -d "$file" -c | tar xf - -C "$dest"
                    else
                        err "需要 zstd 解压 .tar.zst"
                        return 1
                    fi
                    ;;
                *)      tar xf "$file" -C "$dest" ;;
            esac
            ;;

        zip)
            if has_cmd unzip; then
                unzip -qo "$file" -d "$dest"
            elif has_cmd bsdtar; then
                bsdtar xf "$file" -C "$dest"
            else
                err "需要 unzip 或 bsdtar 处理 .zip"
                return 1
            fi
            ;;

        apk)
            tar xzf "$file" -C "$dest" 2>/dev/null || { err "解压 .apk 失败"; return 1; }
            rm -f "$dest"/.PKGINFO "$dest"/.SIGN.* "$dest"/.MTREE "$dest"/.INSTALL 2>/dev/null
            ;;

        kurali)
            local tmp; tmp=$(mktemp -d)
            tar xzf "$file" -C "$tmp" || { rm -rf "$tmp"; return 1; }
            if [[ -d "$tmp/rootfs" ]]; then
                cp -a "$tmp/rootfs"/. "$dest/"
            else
                cp -a "$tmp"/. "$dest/"
            fi
            rm -rf "$tmp"
            ;;

        *)
            err "不支持的格式: $file"
            return 1
            ;;
    esac
    return 0
}

# ═══════════════════════════════════════════════════════
#  辅助函数
# ═══════════════════════════════════════════════════════

# 扁平化单层目录
flatten_extract() {
    local dir="$1"
    local changed=1
    while [[ "$changed" -eq 1 ]]; do
        changed=0
        local count; count=$(find "$dir" -maxdepth 1 -mindepth 1 -type d | wc -l)
        if [[ "$count" -eq 1 ]]; then
            local top; top=$(find "$dir" -maxdepth 1 -mindepth 1 -type d | head -1)
            if [[ -d "${top}/usr" || -d "${top}/bin" || -f "${top}/.AppRun" || -x "${top}/$(basename "$top")" ]]; then
                debug "扁平化: $(basename "$top")"
                local tmp="${dir}.__f__"
                mv "$top" "$tmp"; rm -rf "$dir"; mv "$tmp" "$dir"
                changed=1
            fi
        fi
    done
}

# 查找可执行文件
find_executables() {
    local dir="$1"
    # 先修复常见 bin 目录的执行权限（dpkg-deb -x 可能丢失权限）
    for d in "$dir/usr/bin" "$dir/bin" "$dir/usr/local/bin" "$dir/usr/sbin" "$dir/sbin" "$dir/opt"/*/bin; do
        [[ -d "$d" ]] && chmod +x "$d"/* 2>/dev/null || true
    done
    # 查找所有可执行文件（包括 /opt 等非标准路径）
    local ex; ex=$(find "$dir" -type f -executable 2>/dev/null | sort -u)
    # 兜底：没有任何可执行文件时，列出 bin 目录下所有文件
    if [[ -z "$ex" ]]; then
        for d in "$dir/usr/bin" "$dir/bin" "$dir/usr/local/bin" "$dir/opt"; do
            [[ -d "$d" ]] && find "$d" -maxdepth 3 -type f 2>/dev/null
        done | sort -u
    else
        echo "$ex"
    fi
}

# ═══════════════════════════════════════════════════════
#  依赖检查
# ═══════════════════════════════════════════════════════

check_deps() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        info "系统依赖检查"
        local glibc; glibc=$(ldd --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        info "glibc: ${glibc:-unknown}"
        for lib in libc.so libm.so libdl.so libpthread.so libz.so libssl.so; do
            local found=0
            if has_cmd ldconfig && ldconfig -p 2>/dev/null | grep -qi "${lib%%.*}"; then
                found=1
            fi
            if [[ $found -eq 0 ]]; then
                for d in /lib /lib64 /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu; do
                    [[ -d "$d" ]] && find "$d" -maxdepth 2 -name "${lib}*" -type f 2>/dev/null | head -1 | grep -q . && { found=1; break; }
                done
            fi
            if [[ $found -eq 1 ]]; then
                echo -e "  ${C_GREEN}✓${C_RESET} $lib"
            else
                echo -e "  ${C_YELLOW}?${C_RESET} $lib (未确认)"
            fi
        done
    elif [[ -f "$target" ]]; then
        info "依赖检查: $(basename "$target")"
        local ft; ft=$(file -b "$target" 2>/dev/null)
        if ! echo "$ft" | grep -qi "elf\|dynamically linked"; then
            echo -e "  ${C_YELLOW}!${C_RESET} 非动态链接文件"
            return 0
        fi
        ldd "$target" 2>&1 | while read -r line; do
            if echo "$line" | grep -q "not found"; then
                echo -e "  ${C_RED}✗${C_RESET} $line"
            elif echo "$line" | grep -q "=>"; then
                local lib; lib=$(echo "$line" | awk '{print $1}')
                echo -e "  ${C_GREEN}✓${C_RESET} $lib"
            fi
        done
    else
        die "文件不存在: $target"
    fi
}

# ═══════════════════════════════════════════════════════
#  打包 .kurali 格式
# ═══════════════════════════════════════════════════════

pack_kurali() {
    local file="$1" output="${2:-}"
    [[ -f "$file" ]] || die "文件不存在: $file"

    local filename; filename=$(basename "$file")
    local src_format; src_format=$(detect_format "$filename")
    [[ "$src_format" == "unknown" ]] && die "不支持的格式: $filename"
    [[ "$src_format" == "kurali" ]] && die "文件已经是 .kurali 格式"

    local pkg_name; pkg_name=$(get_pkg_name "$file" "$src_format")
    [[ -z "$pkg_name" || "$pkg_name" == "unknown" ]] && pkg_name="${filename%%.*}"
    pkg_name="${pkg_name,,}"

    local pkg_version; pkg_version=$(get_pkg_version "$file" "$src_format")
    [[ -z "$pkg_version" ]] && pkg_version="unknown"
    [[ -z "$output" ]] && output="${pkg_name}-${pkg_version}.kurali"

    local tmp; tmp=$(mktemp -d)
    local rootfs="${tmp}/rootfs" meta="${tmp}/.kurali" scripts="${tmp}/scripts"
    mkdir -p "$rootfs" "$meta" "$scripts"

    info "打包: ${filename} → ${output}"
    extract_pkg "$file" "$src_format" "$rootfs" || { rm -rf "$tmp"; die "解压失败"; }
    flatten_extract "$rootfs"

    local file_count; file_count=$(find "$rootfs" -type f 2>/dev/null | wc -l)
    local total_size; total_size=$(du -sh "$rootfs" 2>/dev/null | cut -f1)

    cat > "${meta}/manifest.json" << EOF
{
  "name": "${pkg_name}",
  "version": "${pkg_version}",
  "source_format": "${src_format}",
  "source_file": "${filename}",
  "kurali_version": "${KURALI_VERSION}",
  "created": "$(date -Iseconds)",
  "arch": "$(uname -m)",
  "files": ${file_count},
  "size": "${total_size}"
}
EOF

    find "$rootfs" -type f -o -type l 2>/dev/null | sort > "${meta}/files.txt"

    for s in preinst postinst prerm postrm; do
        [[ -f "${rootfs}/DEBIAN/${s}" ]] && cp "${rootfs}/DEBIAN/${s}" "${scripts}/" 2>/dev/null
    done

    if [[ -d "${scripts}" && -n "$(ls -A "$scripts" 2>/dev/null)" ]]; then
        tar czf "$output" -C "$tmp" .kurali rootfs scripts 2>/dev/null
    else
        tar czf "$output" -C "$tmp" .kurali rootfs 2>/dev/null
    fi

    rm -rf "$tmp"
    [[ -f "$output" ]] || { err "打包失败"; return 1; }

    local out_size; out_size=$(du -sh "$output" 2>/dev/null | cut -f1)
    ok "打包完成: ${output} (${out_size}, ${file_count} 个文件)"
    info "运行: kurali --ram ${output}"
}
