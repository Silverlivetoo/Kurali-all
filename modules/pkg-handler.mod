#!/usr/bin/env bash
# pkg-handler.mod — 统一包格式处理（deb/rpm/pacman/appimage/tar/zip/kurali）

# ─── 纯 shell RPM 解压（无需 rpm2cpio/bsdtar）───
# RPM 格式：头部 + cpio 归档。cpio 以 070707 或 070701 开头
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
        # 方法2: RPM lead = 96 字节, 然后跳过签名和元数据段
        # 用 Python 做精确解析（标准库，非额外依赖）
        if has_cmd python3; then
            python3 -c "
import struct, sys
with open('$rpm_file','rb') as f:
    data = f.read()
# RPM: magic 0xED 0xAB 0xEE 0xDB at offset 0
if data[:4] != b'\xed\xab\xee\xdb':
    sys.exit(1)
# 跳过 lead (96字节)
pos = 96
# 跳过 signature header
if pos+8 <= len(data) and data[pos:pos+4] == b'\x8e\xad\xe8\x01':
    il = struct.unpack('>I', data[pos+8:pos+12])[0]
    dl = struct.unpack('>I', data[pos+12:pos+16])[0]
    hdr_bytes = 16 + il * 16 + dl
    if hdr_bytes % 8:
        hdr_bytes += 8 - (hdr_bytes % 8)
    pos = 96 + hdr_bytes
# 跳过 main header
if pos+8 <= len(data) and data[pos:pos+4] == b'\x8e\xad\xe8\x01':
    il = struct.unpack('>I', data[pos+8:pos+12])[0]
    dl = struct.unpack('>I', data[pos+12:pos+16])[0]
    hdr_bytes = 16 + il * 16 + dl
    if hdr_bytes % 8:
        hdr_bytes += 8 - (hdr_bytes % 8)
    pos = pos + hdr_bytes
# 剩余就是压缩的 cpio payload
with open('$payload','wb') as out:
    out.write(data[pos:])
" 2>/dev/null || true
        fi
    fi

    # 检测 payload 压缩格式并解压
    local cpio_file="${tmp}/decompressed.cpio"
    if [[ -s "$payload" ]]; then
        local magic
        magic=$(dd if="$payload" bs=6 count=1 2>/dev/null | xxd -p 2>/dev/null || \
                python3 -c "import sys; sys.stdout.buffer.write(open('$payload','rb').read(6))" 2>/dev/null | xxd -p)
        case "$magic" in
            1f8b*)
                # gzip
                if has_cmd gzip; then
                    gzip -dc "$payload" > "$cpio_file" 2>/dev/null
                elif has_cmd python3; then
                    python3 -c "
import gzip, sys
with gzip.open('$payload','rb') as f: sys.stdout.buffer.write(f.read())
" > "$cpio_file" 2>/dev/null
                fi
                ;;
            fd377a*)
                # XZ (magic: fd 37 7a 58 5a 00)
                if has_cmd xz; then
                    xz -dc "$payload" > "$cpio_file" 2>/dev/null
                elif has_cmd python3; then
                    python3 -c "
import lzma, sys
with open('$payload','rb') as f: sys.stdout.buffer.write(lzma.decompress(f.read()))
" > "$cpio_file" 2>/dev/null
                fi
                ;;
            425a68*)
                # bzip2 (magic: BZh)
                if has_cmd bunzip2; then
                    bunzip2 -dc "$payload" > "$cpio_file" 2>/dev/null
                elif has_cmd python3; then
                    python3 -c "
import bz2, sys
with open('$payload','rb') as f: sys.stdout.buffer.write(bz2.decompress(f.read()))
" > "$cpio_file" 2>/dev/null
                fi
                ;;
            28b52ffd*)
                # zstd (magic: 28 b5 2f fd)
                if has_cmd zstd; then
                    zstd -dc "$payload" > "$cpio_file" 2>/dev/null
                fi
                ;;
            *)
                # 未压缩 cpio
                cp "$payload" "$cpio_file"
                ;;
        esac
    fi

    # 解压 cpio
    if [[ -s "$cpio_file" ]]; then
        if has_cmd cpio; then
            (cd "$dest" && cpio -idm --quiet < "$cpio_file" 2>/dev/null) || \
            (cd "$dest" && cpio -idm < "$cpio_file" 2>/dev/null)
        elif has_cmd python3; then
            python3 -c "
import os, struct, sys

def extract_cpio(cpio_path, dest):
    os.makedirs(dest, exist_ok=True)
    with open(cpio_path, 'rb') as f:
        while True:
            hdr = f.read(110)
            if len(hdr) < 110: break
            if hdr[:6] not in (b'070707', b'070701', b'070702'): break
            if hdr[:6] == b'070707':  # old format (octal)
                namesize = int(hdr[94:100].strip(), 8)
            else:  # new format (hex)
                namesize = int(hdr[94:102], 16)
            name = f.read(namesize).rstrip(b'\x00').decode('utf-8', errors='replace')
            if name == 'TRAILER!!!': break
            if not name or name.startswith('.'): continue
            target = os.path.join(dest, name)
            if hdr[:6] != b'070707':
                mode = int(hdr[14:22], 16)
                filesize = int(hdr[54:62], 16)
            else:
                mode = int(hdr[14:22], 8)
                filesize = int(hdr[54:62], 8)
            if mode & 0o170000 == 0o040000:  # directory
                os.makedirs(target, exist_ok=True)
            elif mode & 0o170000 == 0o100000:  # regular
                os.makedirs(os.path.dirname(target), exist_ok=True)
                content = f.read(filesize)
                with open(target, 'wb') as out:
                    out.write(content)
                os.chmod(target, mode & 0o777)
            elif mode & 0o170000 == 0o120000:  # symlink
                os.makedirs(os.path.dirname(target), exist_ok=True)
                link_target = f.read(filesize).decode('utf-8', errors='replace')
                try: os.symlink(link_target, target)
                except: pass
            # 对齐
            if hdr[:6] != b'070707' and filesize > 0:
                pad = (4 - (filesize % 4)) % 4
                f.read(pad)
extract_cpio('$cpio_file', '$dest')
" 2>/dev/null || { rm -rf "$tmp"; return 1; }
        fi
    fi
    rm -rf "$tmp"
    # 验证是否解出内容
    local count; count=$(find "$dest" -type f 2>/dev/null | wc -l)
    [[ $count -gt 0 ]]
}

# ─── 格式检测 ───
detect_format() {
    local f="$1"
    [[ "$f" =~ \.deb$ ]]          && echo "deb"     && return
    [[ "$f" =~ \.rpm$ ]]          && echo "rpm"     && return
    [[ "$f" =~ \.pacman$ ]]        && echo "pacman"  && return
    [[ "$f" =~ \.pkg\.tar ]]      && echo "pacman"  && return
    [[ "$f" =~ \.kurali$ ]]       && echo "kurali"  && return
    [[ "$f" =~ \.([Aa]pp[Ii]mage)$ ]] && echo "appimage" && return
    # Alpine Linux 包格式（⚠ 不是安卓 APK，是 Alpine Package Keeper）
    [[ "$f" =~ \.apk$ ]]          && echo "apk"     && return
    [[ "$f" =~ \.tar\. || "$f" =~ \.tgz$ || "$f" =~ \.txz$ ]] && echo "tar" && return
    [[ "$f" =~ \.zip$ ]]          && echo "zip"     && return
    echo "unknown"
}

# ─── 包信息提取 ───
get_pkg_name() {
    local file="$1" format="$2" name=""
    case "$format" in
        deb)
            if has_cmd dpkg-deb; then
                name=$(dpkg-deb -f "$file" Package 2>/dev/null)
            elif has_cmd ar; then
                # 备用：用 ar 提取 control.tar 解析 Package 字段
                local tmp_d; tmp_d=$(mktemp -d)
                (cd "$tmp_d" && ar x "$file" control.tar.gz control.tar.xz control.tar.zst control.tar 2>/dev/null)
                for ct in control.tar.xz control.tar.zst control.tar.gz control.tar; do
                    [[ -f "$tmp_d/$ct" ]] && {
                        tar xf "$tmp_d/$ct" -C "$tmp_d" ./control 2>/dev/null && \
                        name=$(grep -i '^Package:' "$tmp_d/control" 2>/dev/null | head -1 | sed 's/^Package:[[:space:]]*//i')
                        break
                    }
                done
                rm -rf "$tmp_d"
            fi
            [[ -z "$name" ]] && name=$(basename "$file" .deb)
            ;;
        rpm)
            if has_cmd rpm; then
                name=$(rpm -qp --qf "%{NAME}" "$file" 2>/dev/null)
            elif has_cmd python3; then
                # 备用：用 python3 解析 RPM header 提取 NAME tag
                name=$(python3 -c "
import struct, sys
try:
    with open('$file','rb') as f: data = f.read()
    if data[:4] != b'\xed\xab\xee\xdb': sys.exit(1)
    pos = 96
    for _ in range(2):  # skip signature + main header
        if pos+16 > len(data): break
        if data[pos:pos+4] != b'\x8e\xad\xe8\x01': break
        il = struct.unpack('>I', data[pos+8:pos+12])[0]
        dl = struct.unpack('>I', data[pos+12:pos+16])[0]
        entries = data[pos+16:pos+16+il*16]
        header_data = data[pos+16+il*16:]
        for i in range(il):
            e = entries[i*16:(i+1)*16]
            tag = struct.unpack('>I', e[:4])[0]
            if tag == 1000:  # RPMTAG_NAME
                off = struct.unpack('>I', e[8:12])[0]
                sz = struct.unpack('>I', e[12:16])[0]
                print(header_data[off:off+sz].split(b'\x00')[0].decode())
                sys.exit(0)
        pos = pos + 16 + il*16 + dl
except: pass
" 2>/dev/null)
            fi
            [[ -z "$name" ]] && name=$(basename "$file" .rpm)
            ;;
        pacman)
            has_cmd bsdtar && name=$(bsdtar xf "$file" -O .PKGINFO 2>/dev/null | grep -E "^pkgname\s*=" | head -1 | sed 's/^pkgname\s*=\s*//')
            [[ -z "$name" ]] && name=$(basename "$file" | sed 's/\.pkg\.tar.*//')
            ;;
        kurali)
            local tmp_k; tmp_k=$(mktemp -d)
            tar xzf "$file" -C "$tmp_k" .kurali/manifest.json 2>/dev/null && \
            name=$(grep '"name"' "$tmp_k/.kurali/manifest.json" 2>/dev/null | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"//;s/".*//')
            rm -rf "$tmp_k"
            ;;
        # Alpine Linux 包格式（alpine-devel@lists.alpinelinux.org 开发，非安卓）
        apk)
            local tmp_a; tmp_a=$(mktemp -d)
            tar xzf "$file" -C "$tmp_a" .PKGINFO 2>/dev/null && \
            name=$(grep -E "^origin\s*=" "$tmp_a/.PKGINFO" 2>/dev/null | head -1 | sed 's/^origin\s*=\s*//')
            [[ -z "$name" ]] && name=$(grep -E "^pkgname\s*=" "$tmp_a/.PKGINFO" 2>/dev/null | head -1 | sed 's/^pkgname\s*=\s*//')
            rm -rf "$tmp_a"
            [[ -z "$name" ]] && name=$(basename "$file" .apk)
            ;;
        appimage)
            name=$(basename "$file" | sed 's/\.[Aa]pp[Ii]mage$//'); name="${name,,}"
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
        deb)  has_cmd dpkg-deb && dpkg-deb -f "$file" Version 2>/dev/null ;;
        rpm)  has_cmd rpm && rpm -qp --qf "%{VERSION}" "$file" 2>/dev/null ;;
        pacman)
            has_cmd bsdtar && bsdtar xf "$file" -O .PKGINFO 2>/dev/null | grep -E "^pkgver\s*=" | head -1 | sed 's/^pkgver\s*=\s*//'
            ;;
        kurali)
            local tmp_k; tmp_k=$(mktemp -d)
            tar xzf "$file" -C "$tmp_k" .kurali/manifest.json 2>/dev/null && \
            grep '"version"' "$tmp_k/.kurali/manifest.json" 2>/dev/null | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"//;s/".*//'
            rm -rf "$tmp_k"
            ;;
        # Alpine Linux 包格式（⚠ 非安卓 APK）
        apk)
            local tmp_a; tmp_a=$(mktemp -d)
            tar xzf "$file" -C "$tmp_a" .PKGINFO 2>/dev/null && \
            grep -E "^pkgver\s*=" "$tmp_a/.PKGINFO" 2>/dev/null | head -1 | sed 's/^pkgver\s*=\s*//'
            rm -rf "$tmp_a"
            ;;
        *)    echo "unknown" ;;
    esac
}

# ─── 提取 ───
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
                local dt
                for dt in data.tar.xz data.tar.zst data.tar.gz data.tar.bz2; do
                    [[ -f "$tmp/$dt" ]] && { tar xf "$tmp/$dt" -C "$dest"; break; }
                done
                rm -rf "$tmp"
            elif has_cmd python3; then
                # 备用：纯 python3 解压 ar + tar
                python3 -c "
import subprocess, tempfile, os, shutil
tmp = tempfile.mkdtemp()
subprocess.run(['ar','x','$file'], cwd=tmp, capture_output=True) if shutil.which('ar') else None
# 尝试各种 tar 压缩格式
for ext in ['data.tar.xz','data.tar.zst','data.tar.gz','data.tar.bz2','data.tar']:
    t = os.path.join(tmp, ext)
    if os.path.exists(t):
        import tarfile
        try: tarfile.open(t).extractall('$dest')
        except: pass
        break
shutil.rmtree(tmp, ignore_errors=True)
" 2>/dev/null || { err "需要 dpkg-deb / ar / python3 处理 .deb"; return 1; }
            else
                err "需要 dpkg-deb 或 ar 来处理 .deb"
                return 1
            fi
            ;;
        rpm)
            if has_cmd rpm2cpio; then
                (cd "$dest" && rpm2cpio "$file" | cpio -idm --quiet 2>/dev/null)
            elif has_cmd bsdtar; then
                bsdtar xf "$file" -C "$dest"
            else
                # 纯 shell 解压 RPM：扫描 cpio magic 跳过 RPM 头部
                _extract_rpm_pure "$file" "$dest" || {
                    err "RPM 解压失败（纯 shell 方法也失败了）"
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
            # 清理元数据
            rm -f "$dest/.PKGINFO" "$dest/.MTREE" "$dest/.INSTALL" "$dest/.BUILDINFO" 2>/dev/null
            ;;
        appimage)
            cp "$file" "$dest/"
            chmod +x "$dest/$(basename "$file")"
            # 方法1: --appimage-extract（官方方法）
            local extracted=0
            (cd "$dest" && "./$(basename "$file")" --appimage-extract > /dev/null 2>&1) && \
            { rm "$dest/$(basename "$file")"; extracted=1; }
            # 方法2: unsquashfs（SquashFS 类型 AppImage 的备用）
            if [[ $extracted -eq 0 ]] && has_cmd unsquashfs; then
                local offset; offset=$(LANG=C grep -aob 'hsqs' "$file" 2>/dev/null | head -1 | cut -d: -f1)
                if [[ -n "$offset" ]]; then
                    rm "$dest/$(basename "$file")"
                    local sqf="${dest}/squashfs.img"
                    dd if="$file" bs=1 skip="$offset" 2>/dev/null > "$sqf" && \
                    unsquashfs -d "$dest/squashfs-root" -f "$sqf" > /dev/null 2>&1 && \
                    { mv "$dest/squashfs-root"/* "$dest/" 2>/dev/null; rm -rf "$dest/squashfs-root" "$sqf"; extracted=1; }
                fi
            fi
            # 方法3: 直接复制二进制（最后兜底）
            if [[ $extracted -eq 0 ]]; then
                warn "AppImage 提取失败，保留原始文件直接执行"
            fi
            ;;
        tar)
            local ext="${file##*.}"
            case "$ext" in
                gz|tgz)  tar xzf "$file" -C "$dest" ;;
                xz)      tar xJf "$file" -C "$dest" ;;
                bz2)     tar xjf "$file" -C "$dest" ;;
                zst)
                    if has_cmd zstd; then
                        zstd -d "$file" -c | tar xf - -C "$dest"
                    elif has_cmd python3; then
                        python3 -c "
import subprocess, tempfile, os
tmp = tempfile.mktemp(suffix='.tar')
subprocess.run(['python3','-c',f\"import zstandard as z; open('{tmp}','wb').write(z.ZstdDecompressor().decompress(open('{file}','rb').read()))\"], capture_output=True)
import tarfile
tarfile.open(tmp).extractall('{dest}')
os.unlink(tmp)
" 2>/dev/null || tar xf "$file" -C "$dest"
                    else
                        tar xf "$file" -C "$dest"
                    fi
                    ;;
                *)       tar xf "$file" -C "$dest" ;;
            esac
            ;;
        zip)
            if has_cmd unzip; then
                unzip -qo "$file" -d "$dest"
            elif has_cmd python3; then
                python3 -c "import zipfile; zipfile.ZipFile('$file').extractall('$dest')"
            elif has_cmd bsdtar; then
                bsdtar xf "$file" -C "$dest"
            else
                err "需要 unzip/python3/bsdtar 处理 .zip"
                return 1
            fi
            ;;
        # Alpine Linux 包格式（⚠ 不是安卓 APK！alpine .apk = Alpine Package Keeper）
        # 内部是 tar.gz，含 .PKGINFO 元数据 + .SIGN.* 签名 + 实际文件
        apk)
            tar xzf "$file" -C "$dest" 2>/dev/null || {
                err "解压 .apk 失败"
                return 1
            }
            # 清理 Alpine 元数据和签名文件
            rm -f "$dest"/.PKGINFO "$dest"/.SIGN.* "$dest"/.MTREE "$dest"/.INSTALL 2>/dev/null
            ;;
        kurali)
            local tmp_k; tmp_k=$(mktemp -d)
            tar xzf "$file" -C "$tmp_k" || { rm -rf "$tmp_k"; return 1; }
            if [[ -d "$tmp_k/rootfs" ]]; then
                cp -a "$tmp_k/rootfs"/. "$dest/"
            else
                cp -a "$tmp_k"/. "$dest/"
            fi
            rm -rf "$tmp_k"
            ;;
        *)
            err "未知格式: $file"
            return 1
            ;;
    esac
    return 0
}

# ─── 扁平化单层目录（递归处理多层嵌套）───
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

# ─── 查找可执行文件 ───
find_executables() {
    local dir="$1"
    find "$dir/usr/bin" "$dir/bin" "$dir/usr/local/bin" "$dir/usr/sbin" "$dir/sbin" \
        "$dir" -maxdepth 2 -type f -executable 2>/dev/null | sort -u
}

# ─── 依赖检查 ───
check_deps() {
    local target="${1:-}"
    if [[ -z "$target" ]]; then
        info "系统依赖检查"
        local glibc; glibc=$(ldd --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        info "glibc: ${glibc:-unknown}"
        local libs="libc.so libm.so libdl.so libpthread.so libz.so libssl.so"
        for lib in $libs; do
            local found=0
            # 方法1: ldconfig
            if has_cmd ldconfig && ldconfig -p 2>/dev/null | grep -qi "${lib%%.*}"; then
                found=1
            fi
            # 方法2: 查找常见库路径
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
        # 检查是否是 ELF 二进制
        local ft; ft=$(file -b "$target" 2>/dev/null)
        if ! echo "$ft" | grep -qi "elf\|dynamically linked"; then
            echo -e "  ${C_YELLOW}!${C_RESET} 非动态链接文件 (${ft})"
            info "仅 ELF 二进制可检查依赖"
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

# ─── 打包 .kurali 格式 ───
# 将任意支持的格式转为 .kurali 归档
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
    local rootfs="${tmp}/rootfs"
    local meta="${tmp}/.kurali"
    local scripts="${tmp}/scripts"
    mkdir -p "$rootfs" "$meta" "$scripts"

    info "打包: ${filename} → ${output}"

    # 解压源包
    extract_pkg "$file" "$src_format" "$rootfs" || { rm -rf "$tmp"; die "解压失败"; }
    flatten_extract "$rootfs"

    # 生成 manifest.json
    cat > "${meta}/manifest.json" << EOF
{
  "name": "${pkg_name}",
  "version": "${pkg_version}",
  "source_format": "${src_format}",
  "source_file": "${filename}",
  "kurali_version": "${KURALI_VERSION}",
  "created": "$(date -Iseconds)",
  "arch": "$(uname -m)"
}
EOF

    # 生成文件清单
    find "$rootfs" -type f -o -type l 2>/dev/null | sort > "${meta}/files.txt"

    # 提取维护脚本（如果有的话）
    for s in preinst postinst prerm postrm pre-install post-install; do
        if [[ -f "${rootfs}/DEBIAN/${s}" ]]; then
            cp "${rootfs}/DEBIAN/${s}" "${scripts}/" 2>/dev/null
        fi
    done

    # 计算文件数和大小
    local file_count; file_count=$(find "$rootfs" -type f 2>/dev/null | wc -l)
    local total_size; total_size=$(du -sh "$rootfs" 2>/dev/null | cut -f1)
    # 重新生成完整的 manifest.json（避免 sed 在不同平台行为不一致）
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

    # 打包（一次性完成，避免第二次 tar 覆盖第一次输出）
    if [[ -d "${scripts}" && -n "$(ls -A "$scripts" 2>/dev/null)" ]]; then
        tar czf "$output" -C "$tmp" .kurali rootfs scripts 2>/dev/null
    else
        tar czf "$output" -C "$tmp" .kurali rootfs 2>/dev/null
    fi

    rm -rf "$tmp"

    # 验证打包结果
    if [[ ! -f "$output" ]]; then
        err "打包失败: 输出文件未生成"
        return 1
    fi

    # 检查打包内容是否有效
    local verify_tmp; verify_tmp=$(mktemp -d)
    if tar tzf "$output" 2>/dev/null | head -5 | grep -q ".kurali/manifest.json"; then
        :  # 打包内容有效
    else
        warn "警告: 打包内容可能不完整"
    fi
    rm -rf "$verify_tmp"

    local out_size; out_size=$(du -sh "$output" 2>/dev/null | cut -f1)
    ok "打包完成: ${output} (${out_size}, ${file_count} 个文件)"
    info "来源: ${filename} [${src_format}] → .kurali"
    echo -e "  ${C_CYAN}直接运行:${C_RESET} kurali --ram ${output}"
    echo -e "  ${C_CYAN}安装:${C_RESET} kurali i ${output}"
}
