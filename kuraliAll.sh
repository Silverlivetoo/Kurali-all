#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════
#  KuraliAll v3.1.3 — 全能 Linux 包管理器
#  纯 Shell | 零 Python 依赖 | 离线工作 | 跨发行版
# ═══════════════════════════════════════════════════════

set -uo pipefail

# ─── 原始参数（供 need_root 自动提权使用）────
_K_ARGS=("$@")

# ─── 路径 ───
_K_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KURALI_MODULES_DIR="${_K_DIR}/modules"
export KURALI_CONFIG_DIR="${_K_DIR}/config"
export KURALI_HOOKS_DIR="${_K_DIR}/hooks"

# ─── 加载核心模块 ───
source "${KURALI_MODULES_DIR}/core.mod"

# ─── 加载功能模块 ───
load_module "system"      || die "核心模块 system.mod 加载失败"
load_module "pkg-handler" || die "核心模块 pkg-handler.mod 加载失败"
load_module "docker-run"  2>/dev/null
load_module "desktop"     2>/dev/null
load_module "service"     2>/dev/null
load_module "update"      2>/dev/null

# ─── 加载钩子 ───
[[ -f "${KURALI_HOOKS_DIR}/pre-install.mod" ]]  && source "${KURALI_HOOKS_DIR}/pre-install.mod"
[[ -f "${KURALI_HOOKS_DIR}/post-install.mod" ]] && source "${KURALI_HOOKS_DIR}/post-install.mod"

# ═══════════════════════════════════════════════════════
#  命令实现
# ═══════════════════════════════════════════════════════

# ─── 安装 ───
cmd_install() {
    local file="$1"; shift
    local pkg_name="${1:-}"

    [[ -f "$file" ]] || die "文件不存在: $file"

    local filename; filename=$(basename "$file")
    local format; format=$(detect_format "$filename")
    [[ "$format" == "unknown" ]] && die "不支持的格式: $filename"
    info "格式: ${format}  文件: ${filename}"

    # 确定包名
    [[ -z "$pkg_name" ]] && pkg_name=$(get_pkg_name "$file" "$format")
    [[ -z "$pkg_name" || "$pkg_name" == "unknown" ]] && pkg_name="${filename%%.*}"
    pkg_name="${pkg_name,,}"

    local pkg_dir="${PKG_DIR}/${pkg_name}"
    local extract_dir="${pkg_dir}/rootfs"
    mkdir -p "$extract_dir"
    rm -rf "${extract_dir:?}/"* 2>/dev/null || true

    # pre-install 钩子
    declare -F pre_install_hook >/dev/null && pre_install_hook "$file" "$extract_dir"

    if [[ "$MODE_SYSTEM" -eq 1 ]]; then
        # ─── 系统安装模式 ───
        need_root
        info "⚠ 直接系统安装模式"
        [[ "$MODE_BACKUP" -eq 1 ]] && info "启用文件备份 (备份在 ${BACKUP_DIR})"
        danger_confirm "将 ${pkg_name} 的文件直接安装到系统根目录?"

        extract_pkg "$file" "$format" "$extract_dir" || die "解压失败"
        flatten_extract "$extract_dir"
        _fix_perms "$extract_dir"

        # 执行维护脚本
        for script in preinst postinst; do
            if [[ -f "${extract_dir}/DEBIAN/${script}" ]]; then
                info "执行 ${script}..."
                (cd "$extract_dir" && sh "DEBIAN/${script}" install 2>/dev/null) || warn "${script} 执行出错"
            fi
        done

        # 复制到系统
        info "复制文件到系统..."
        local file_count=0
        for dir in usr bin sbin lib lib32 lib64 libx32 etc var opt; do
            if [[ -d "${extract_dir}/${dir}" ]]; then
                while IFS= read -r f; do
                    safe_copy "$f" "/${dir}/${f#${extract_dir}/${dir}/}"
                    file_count=$((file_count+1))
                done < <(find "${extract_dir}/${dir}" -type f 2>/dev/null)
            fi
        done
        info "已复制 ${file_count} 个文件"
    else
        # ─── 默认：隔离目录 + 符号链接 ───
        extract_pkg "$file" "$format" "$extract_dir" || {
            rm -rf "$pkg_dir"
            if [[ "$MODE_DOCKER" -eq 1 ]] && declare -F detect_container_rt >/dev/null && detect_container_rt; then
                warn "解压失败，Docker 兜底"
                docker_fallback "$file" "$pkg_name"
                return 0
            fi
            die "解压失败: $file"
        }
        flatten_extract "$extract_dir"
        _fix_perms "$extract_dir"
    fi

    # .kurali 格式维护脚本
    if [[ "$format" == "kurali" ]]; then
        local tmp_scripts; tmp_scripts=$(mktemp -d)
        tar xzf "$file" -C "$tmp_scripts" scripts/ 2>/dev/null || true
        if [[ -d "${tmp_scripts}/scripts" ]]; then
            for s in pre-install preinst; do
                [[ -f "${tmp_scripts}/scripts/${s}" ]] && {
                    info "执行 .kurali/${s}..."
                    chmod +x "${tmp_scripts}/scripts/${s}"
                    (cd "$extract_dir" && "${tmp_scripts}/scripts/${s}" install 2>/dev/null) || warn "${s} 执行出错"
                }
            done
        fi
        rm -rf "$tmp_scripts"
    fi

    # post-install 钩子
    declare -F post_install_hook >/dev/null && post_install_hook "$file" "$extract_dir" "$pkg_name"

    # 符号链接
    if [[ "$MODE_SYSTEM" -ne 1 ]]; then
        local link_dir="/usr/local/bin"
        [[ ! -w "$link_dir" ]] && { link_dir="${HOME}/.local/bin"; mkdir -p "$link_dir" 2>/dev/null; }
        local linked=0
        while IFS= read -r ex; do
            [[ -z "$ex" ]] && continue
            local bn; bn=$(basename "$ex")
            if [[ "$bn" == "AppRun" && "$format" == "appimage" ]]; then
                ln -sf "$ex" "${link_dir}/${pkg_name}" 2>/dev/null || true
                linked=$((linked+1))
                continue
            fi
            if [[ ! -f "${link_dir}/${bn}" ]]; then
                ln -sf "$ex" "${link_dir}/${bn}" 2>/dev/null || true
                linked=$((linked+1))
            fi
        done < <(find_executables "$extract_dir")
        [[ $linked -gt 0 ]] && info "已链接 ${linked} 个命令到 ${link_dir}"
    fi

    # 桌面集成：优先使用包内 .desktop，没有则自动生成
    if declare -F install_desktop_entry >/dev/null; then
        # 查找包内自带的 .desktop 文件
        local pkg_desktop=""
        pkg_desktop=$(find "$extract_dir/usr/share/applications" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null | head -1)

        if [[ -n "$pkg_desktop" ]]; then
            # 包内有 .desktop → 直接用，修复路径
            info "使用包内桌面文件: $(basename "$pkg_desktop")"
            install_desktop_from_pkg "$pkg_desktop" "$pkg_name" "$extract_dir" || warn "桌面集成失败"
        else
            # 包内没有 .desktop → 自动生成（全目录搜索可执行文件）
            local desktop_ex
            desktop_ex=$(find "$extract_dir" -maxdepth 1 -type f -executable 2>/dev/null | head -1)
            [[ -z "$desktop_ex" ]] && desktop_ex=$(find "$extract_dir/usr/bin" "$extract_dir/bin" "$extract_dir/usr/local/bin" \
                -maxdepth 1 -type f -executable 2>/dev/null | head -1)
            # AppImage 兜底：找 AppRun
            [[ -z "$desktop_ex" ]] && desktop_ex=$(find "$extract_dir" -name "AppRun" -type f 2>/dev/null | head -1)
            if [[ -n "$desktop_ex" ]]; then
                chmod +x "$desktop_ex" 2>/dev/null || true
                local icon_file=""
                for idir in \
                    "$extract_dir/usr/share/pixmaps" \
                    "$extract_dir/usr/share/icons/hicolor/256x256/apps" \
                    "$extract_dir/usr/share/icons/hicolor/128x128/apps" \
                    "$extract_dir/usr/share/icons/hicolor/64x64/apps" \
                    "$extract_dir/usr/share/icons/hicolor/48x48/apps" \
                    "$extract_dir/usr/share/icons" \
                    "$extract_dir"; do
                    [[ -d "$idir" ]] || continue
                    icon_file=$(find "$idir" -maxdepth 2 \( -name "*.png" -o -name "*.svg" -o -name "*.xpm" \) -type f 2>/dev/null | head -1)
                    [[ -n "$icon_file" ]] && break
                done
                install_desktop_entry "$pkg_name" "$pkg_name" "$desktop_ex" "$icon_file" || warn "桌面集成失败"
            fi
        fi
    fi

    # 保存元数据
    local pkg_version; pkg_version=$(get_pkg_version "$file" "$format")
    cat > "${pkg_dir}/${pkg_name}.info" << EOF
name=${pkg_name}
version=${pkg_version:-unknown}
format=${format}
source=$(basename "$file")
installed=$(date -Iseconds)
mode=$( [[ $MODE_SYSTEM -eq 1 ]] && echo "system" || echo "sandbox" )
path=${extract_dir}
kuraliAll=${KURALI_VERSION}
EOF
    find "$extract_dir" -type f 2>/dev/null > "${pkg_dir}/${pkg_name}.files"

    ok "安装完成: ${pkg_name} (${pkg_version:-未知版本})"
    [[ "$MODE_SYSTEM" -ne 1 ]] && info "安装路径: ${extract_dir}"
}

# ─── 卸载 ───
cmd_remove() {
    local name="$1"; [[ -z "$name" ]] && die "用法: kurali r <包名>"
    local pkg_dir="${PKG_DIR}/${name}"
    [[ -d "$pkg_dir" ]] || die "包不存在: ${name}"

    confirm "卸载 ${name}?" || { info "取消"; return 0; }

    local info_file="${pkg_dir}/${name}.info"
    local mode="sandbox"
    [[ -f "$info_file" ]] && mode=$(grep "^mode=" "$info_file" | cut -d= -f2)

    if [[ "$mode" == "system" ]]; then
        danger_confirm "此包以系统模式安装，卸载将删除系统中的文件 (有备份)?"
        local files_file="${pkg_dir}/${name}.files"
        if [[ -f "$files_file" ]]; then
            while IFS= read -r f; do
                safe_sudo rm -f "$f" 2>/dev/null || true
            done < "$files_file"
        fi
    fi

    # 移除符号链接
    if [[ -f "${pkg_dir}/${name}.files" ]]; then
        while IFS= read -r f; do
            local bn; bn=$(basename "$f")
            for ldir in "/usr/local/bin" "${HOME}/.local/bin"; do
                if [[ -L "${ldir}/${bn}" ]]; then
                    local target; target=$(readlink -f "${ldir}/${bn}")
                    [[ "$target" == "${pkg_dir}"* ]] && rm -f "${ldir}/${bn}" 2>/dev/null || true
                fi
            done
        done < "${pkg_dir}/${name}.files"
    fi

    declare -F remove_desktop_entry >/dev/null && remove_desktop_entry "$name" 2>/dev/null || true
    rm -rf "$pkg_dir"
    ok "已卸载: ${name}"
}

# ─── 列表 ───
cmd_list() {
    local entries=0 header_printed=0
    for dir in "$PKG_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local name; name=$(basename "$dir")
        local info_file="${dir}/${name}.info"
        if [[ $header_printed -eq 0 ]]; then
            echo -e "\n${C_BOLD}已安装的包:${C_RESET}\n"
            printf "  ${C_CYAN}%-20s %-12s %-8s %-8s %s${C_RESET}\n" "包名" "格式" "版本" "模式" "安装日期"
            header_printed=1
        fi
        if [[ -f "$info_file" ]]; then
            local ver fmt mode installed
            ver=$(grep "^version=" "$info_file" | cut -d= -f2)
            fmt=$(grep "^format=" "$info_file" | cut -d= -f2)
            mode=$(grep "^mode=" "$info_file" | cut -d= -f2)
            installed=$(grep "^installed=" "$info_file" | cut -d= -f2 | cut -dT -f1)
            printf "  %-20s %-12s %-8s %-8s %s\n" "$name" "$fmt" "${ver:-?}" "${mode:-sandbox}" "${installed:-?}"
        else
            printf "  %-20s\n" "$name"
        fi
        entries=$((entries+1))
    done
    [[ $entries -eq 0 ]] && info "没有已安装的包"
    echo ""
}

# ─── 搜索 ───
cmd_search() {
    local kw="$1"; [[ -z "$kw" ]] && die "用法: kurali s <关键词>"
    local found=0
    for dir in "$PKG_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local name; name=$(basename "$dir")
        if echo "$name" | grep -qi "$kw"; then
            [[ $found -eq 0 ]] && echo -e "\n${C_BOLD}搜索结果:${C_RESET}"
            local ver; ver=$(grep "^version=" "${dir}/${name}.info" 2>/dev/null | cut -d= -f2)
            echo -e "  ${C_GREEN}${name}${C_RESET} (${ver:-未知版本})"
            found=$((found+1))
        fi
    done
    [[ $found -eq 0 ]] && info "未找到匹配 '${kw}' 的包"
}

# ─── 详情 ───
cmd_info() {
    local name="$1"; [[ -z "$name" ]] && die "用法: kurali f <包名>"
    local info_file="${PKG_DIR}/${name}/${name}.info"
    [[ -f "$info_file" ]] || die "包不存在: ${name}"

    echo -e "\n${C_BOLD}包详情: ${name}${C_RESET}\n"
    while IFS='=' read -r key val; do
        [[ -z "$key" ]] && continue
        printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "${key}:" "$val"
    done < "$info_file"

    local files_file="${PKG_DIR}/${name}/${name}.files"
    [[ -f "$files_file" ]] && printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "files:" "$(wc -l < "$files_file") 个文件"
    printf "  ${C_CYAN}%-12s${C_RESET} %s\n" "size:" "$(du -sh "${PKG_DIR}/${name}" 2>/dev/null | cut -f1)"
    echo ""
}

# ─── 自安装 ───
cmd_install_self() {
    need_root
    info "安装 KuraliAll 到系统..."
    local target="/var/lib/kuraliAll"
    mkdir -p "$target"
    cp -a "${_K_DIR}/modules" "${_K_DIR}/config" "${_K_DIR}/hooks" "${_K_DIR}/kuraliAll.sh" "$target/" 2>/dev/null || true
    chmod +x "${target}/kuraliAll.sh"
    mkdir -p "${target}"/{db,logs,pkg,backup,cache}
    chmod 777 "${target}/logs" "${target}/cache" 2>/dev/null || true

    cat > "/usr/local/bin/kurali" << 'EOF'
#!/bin/bash
exec /var/lib/kuraliAll/kuraliAll.sh "$@"
EOF
    chmod +x "/usr/local/bin/kurali"

    echo "$KURALI_VERSION" > "$target/version"

    # 保存 commit hash
    if [[ -d "${_K_DIR}/.git" ]] && has_cmd git; then
        git -C "$_K_DIR" log --oneline -1 2>/dev/null | awk '{print $1}' > "$target/commit"
    fi
    ok "安装完成！使用 'kurali help' 查看帮助"
}

# ─── 自卸载 ───
cmd_uninstall_self() {
    need_root
    local target="/var/lib/kuraliAll"
    local bin="/usr/local/bin/kurali"

    if [[ ! -d "$target" && ! -f "$bin" ]]; then
        info "KuraliAll 似乎未安装"; return 0
    fi

    local pkg_count=0
    [[ -d "${target}/pkg" ]] && pkg_count=$(find "${target}/pkg" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

    danger_confirm "确定要卸载 KuraliAll? 此操作不可撤销!"

    # 移除命令
    [[ -f "$bin" ]] && { rm -f "$bin"; ok "已移除 ${bin}"; }

    # 清理桌面文件
    for uh in /root /home/*; do
        [[ -d "$uh" ]] || continue
        find "${uh}/.local/share/applications" -name "kurali-*.desktop" -type f -delete 2>/dev/null
        find "${uh}/.local/share/icons/hicolor/256x256/apps" -name "kurali-*" -type f -delete 2>/dev/null
    done

    # 删除安装目录（保留用户数据）
    if [[ -d "$target" ]]; then
        rm -f "${target}/kuraliAll.sh" "${target}/version"
        rm -rf "${target}/modules" "${target}/config" "${target}/hooks" "${target}/cache"
        ok "已删除程序文件"
        if [[ $pkg_count -gt 0 ]]; then
            info "已安装的包数据保留在 ${target}/pkg"
            info "完全删除: sudo rm -rf ${target}"
        else
            rm -rf "$target"
            ok "已删除 ${target}"
        fi
    fi

    ok "KuraliAll 已卸载"
}

# ─── 版本信息 ───
cmd_version() {
    echo -e "\n${C_BOLD}KuraliAll 版本信息:${C_RESET}"
    echo -e "  当前: ${C_GREEN}v${KURALI_VERSION}${C_RESET}"
    local sys_ver="" sys_commit=""
    [[ -f /var/lib/kuraliAll/version ]] && sys_ver=$(cat /var/lib/kuraliAll/version)
    [[ -f /var/lib/kuraliAll/commit ]] && sys_commit=$(cat /var/lib/kuraliAll/commit)
    echo -e "  系统: ${C_GREEN}${sys_ver:-未安装}${C_RESET}"
    [[ -n "$sys_commit" ]] && echo -e "  commit: ${C_GRAY}${sys_commit}${C_RESET}"
    echo ""
}

# ═══════════════════════════════════════════════════════
#  主入口
# ═══════════════════════════════════════════════════════

main() {
    init_dirs

    local cmd="" args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -D|--docker)       MODE_DOCKER=1; shift ;;
            --system)          MODE_SYSTEM=1; shift ;;
            --no-backup)       MODE_BACKUP=0; shift ;;
            --distro=*)        USER_DISTRO="${1#*=}"; shift ;;
            --select-distro)   detect_distro; select_distro; shift ;;
            --install-self)    cmd_install_self; exit $? ;;
            -v|--verbose)      VERBOSE=1; shift ;;
            -q|--quiet)        QUIET=1; shift ;;
            -y|--yes)          NO_CONFIRM=1; shift ;;
            -h|--help|help)    show_help; exit 0 ;;
            -*)
                local _opt_err="未知选项: ${1} — 用 kurali help 查看帮助"
                err "$_opt_err"; exit 1
                ;;
            *)
                if [[ -z "$cmd" ]]; then cmd="$1"; else args+=("$1"); fi
                shift ;;
        esac
    done

    [[ -z "$cmd" ]] && { show_help; exit 0; }

    # 命令路由
    case "$cmd" in
        i|install|add)
            [[ ${#args[@]} -lt 1 ]] && die "用法: kurali i <文件>"
            cmd_install "${args[@]}"
            ;;
        r|remove|rm)
            [[ ${#args[@]} -lt 1 ]] && die "用法: kurali r <包名>"
            cmd_remove "${args[0]}"
            ;;
        l|list|ls)       cmd_list ;;
        s|search|find)
            [[ ${#args[@]} -lt 1 ]] && die "用法: kurali s <关键词>"
            cmd_search "${args[0]}"
            ;;
        f|info|show)
            [[ ${#args[@]} -lt 1 ]] && die "用法: kurali f <包名>"
            cmd_info "${args[0]}"
            ;;
        pack)
            [[ ${#args[@]} -lt 1 ]] && die "用法: kurali pack <文件> [输出名.kurali]"
            pack_kurali "${args[@]}"
            ;;
        native)
            [[ ${#args[@]} -lt 1 ]] && die "用法: kurali native <包名>"
            native_install "${args[0]}"
            ;;
        deps|dep)        check_deps "${args[0]:-}" ;;
        boot)
            [[ ${#args[@]} -lt 1 ]] && die "用法: kurali boot <enable|disable|status> [服务名]"
            declare -F manage_service >/dev/null && manage_service "${args[0]}" "${args[1]:-}" || die "service 模块不可用"
            ;;
        update|ver|version)   cmd_version ;;
        self-update|upgrade)
            declare -F cmd_self_update >/dev/null && cmd_self_update || die "update 模块不可用"
            ;;
        uninstall-self)
            cmd_uninstall_self
            ;;
        network)
            declare -F cmd_network >/dev/null && cmd_network "${args[@]}" || die "update 模块不可用"
            ;;
    esac

    # case 未匹配到任何命令
    if [[ -n "$cmd" ]]; then
        local _err_msg="未知命令: ${cmd} — 用 kurali help 查看帮助"
        err "$_err_msg"
        exit 1
    fi
}

main "$@"
