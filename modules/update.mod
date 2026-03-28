#!/usr/bin/env bash
# update.mod — 联网自更新模块
# KuraliAll v3.0+

# ─── 配置 ───
KURALI_REPO_URL="https://gitee.com/AY77-OP/kurali-all"
KURALI_RAW_URL="${KURALI_REPO_URL}/raw/main"
KURALI_UPDATE_BRANCH="main"

# 联网许可文件
_update_consent_file="${KURALI_HOME}/.network_consent"

# ─── 联网许可 ───
check_network_consent() {
    # 用户已全局同意
    if [[ -f "$_update_consent_file" ]]; then
        local granted; granted=$(head -1 "$_update_consent_file" 2>/dev/null)
        [[ "$granted" == "granted" ]] && return 0
    fi
    return 1
}

ask_network_consent() {
    echo ""
    echo -e "${C_YELLOW}${C_BOLD}╔══════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}║          ⚠  联网许可请求                    ║${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}╚══════════════════════════════════════════════╝${C_RESET}"
    echo ""
    echo -e "  KuraliAll 需要连接网络以检查更新。"
    echo ""
    echo -e "  ${C_CYAN}目标:${C_RESET}  ${KURALI_REPO_URL}"
    echo -e "  ${C_CYAN}用途:${C_RESET}  检查版本、下载更新文件"
    echo -e "  ${C_CYAN}数据:${C_RESET}  不会上传任何本地数据"
    echo ""
    echo -e "  ${C_YELLOW}你可以随时撤销许可: kurali network revoke${C_RESET}"
    echo ""

    [[ "$NO_CONFIRM" -eq 1 ]] && { _save_consent; return 0; }

    read -rp "$(echo -e "  ${C_GREEN}允许联网？[Y/n]: ${C_RESET}")" ans
    if [[ -z "$ans" || "$ans" == "y" || "$ans" == "Y" ]]; then
        _save_consent
        ok "已授予联网许可"
        return 0
    else
        info "已拒绝联网，操作取消"
        return 1
    fi
}

_save_consent() {
    mkdir -p "$(dirname "$_update_consent_file")" 2>/dev/null || true
    echo "granted" > "$_update_consent_file" 2>/dev/null || true
    echo "$(date -Iseconds) consent_granted" >> "${KURALI_HOME}/logs/network.log" 2>/dev/null || true
}

revoke_consent() {
    rm -f "$_update_consent_file" 2>/dev/null || true
    ok "已撤销联网许可"
    info "下次联网操作将重新请求授权"
}

# ─── 网络请求（统一出口，带日志）───
_fetch() {
    local url="$1" output="$2"
    if ! check_network_consent; then
        ask_network_consent || return 1
    fi

    local log_line="[FETCH] $(date -Iseconds) $url"
    echo "$log_line" >> "${KURALI_HOME}/logs/network.log" 2>/dev/null || true

    if has_cmd curl; then
        curl -fsSL --connect-timeout 10 --max-time 60 -o "$output" "$url" 2>/dev/null
    elif has_cmd wget; then
        wget -q --timeout=10 -O "$output" "$url" 2>/dev/null
    else
        err "需要 curl 或 wget 来联网"
        return 1
    fi
}

# ─── 版本比较 ───
# 返回: 0=远程更新, 1=已是最新, 2=出错
_version_gt() {
    # 简单语义版本比较: v1 > v2 → 0
    local v1="$1" v2="$2"
    v1="${v1#v}"; v2="${v2#v}"
    [[ "$v1" == "$v2" ]] && return 1
    local IFS='.'
    local -a a1=($v1) a2=($v2)
    for i in 0 1 2; do
        local n1="${a1[$i]:-0}" n2="${a2[$i]:-0}"
        [[ "$n1" -gt "$n2" ]] && return 0
        [[ "$n1" -lt "$n2" ]] && return 1
    done
    return 1
}

# ─── 获取远程版本 ───
_get_remote_version() {
    local tmp_ver; tmp_ver=$(mktemp)
    _fetch "${KURALI_RAW_URL}/modules/core.mod" "$tmp_ver" || {
        rm -f "$tmp_ver"; return 1
    }
    local remote_ver
    remote_ver=$(grep '^KURALI_VERSION=' "$tmp_ver" 2>/dev/null | head -1 | sed 's/.*"\(.*\)".*/\1/')
    rm -f "$tmp_ver"
    [[ -z "$remote_ver" ]] && return 1
    echo "$remote_ver"
}

# 获取远程 commit hash
_get_remote_commit() {
    local tmp; tmp=$(mktemp)
    # 用 Gitee API 获取最新 commit
    if has_cmd curl; then
        curl -fsSL --connect-timeout 10 --max-time 15 \
            "https://gitee.com/api/v5/repos/AY77-OP/kurali-all/commits?sha=${KURALI_UPDATE_BRANCH}&per_page=1" \
            2>/dev/null | grep -o '"sha":"[^"]*"' | head -1 | sed 's/"sha":"//;s/"//' > "$tmp"
    elif has_cmd wget; then
        wget -q --timeout=10 -O - \
            "https://gitee.com/api/v5/repos/AY77-OP/kurali-all/commits?sha=${KURALI_UPDATE_BRANCH}&per_page=1" \
            2>/dev/null | grep -o '"sha":"[^"]*"' | head -1 | sed 's/"sha":"//;s/"//' > "$tmp"
    fi
    local hash; hash=$(cat "$tmp" 2>/dev/null)
    rm -f "$tmp"
    echo "${hash:0:7}"
}

# ─── 应用文件到本地 ───
_apply_files() {
    local src_dir="$1"

    # 备份当前核心文件
    info "备份当前版本..."
    local backup_ts; backup_ts=$(date +%s)
    local update_backup="${KURALI_HOME}/backup/update-${backup_ts}"
    mkdir -p "$update_backup"
    cp -a "${_K_DIR}/kuraliAll.sh" "$update_backup/" 2>/dev/null || true
    [[ -d "${_K_DIR}/modules" ]] && cp -a "${_K_DIR}/modules" "$update_backup/" 2>/dev/null || true
    [[ -d "${_K_DIR}/config" ]] && cp -a "${_K_DIR}/config" "$update_backup/" 2>/dev/null || true
    [[ -d "${_K_DIR}/hooks" ]] && cp -a "${_K_DIR}/hooks" "$update_backup/" 2>/dev/null || true

    # 应用更新
    info "应用更新..."
    cp -af "${src_dir}/kuraliAll.sh" "${_K_DIR}/kuraliAll.sh" 2>/dev/null || true
    chmod +x "${_K_DIR}/kuraliAll.sh" 2>/dev/null || true

    for d in modules config hooks; do
        if [[ -d "${src_dir}/${d}" ]]; then
            for f in "${src_dir}/${d}/"*; do
                [[ -f "$f" ]] && cp -af "$f" "${_K_DIR}/${d}/" 2>/dev/null || true
            done
        fi
    done
}

# ─── 下载并应用更新 ───
_apply_update() {
    # 方法1: 如果在 git 仓库里，直接 git pull
    if [[ -d "${_K_DIR}/.git" ]] && has_cmd git; then
        info "通过 git 拉取更新..."
        if (cd "$_K_DIR" && git pull --ff-only origin "${KURALI_UPDATE_BRANCH}" 2>/dev/null); then
            chmod +x "${_K_DIR}/kuraliAll.sh" 2>/dev/null || true
            echo "$(date -Iseconds) update_via_git" >> "${KURALI_HOME}/logs/network.log" 2>/dev/null || true
            return 0
        else
            warn "git pull 失败，尝试 zip 下载..."
        fi
    fi

    # 方法2: zip 或 git clone 兜底
    local tmp_dir; tmp_dir=$(mktemp -d)
    local archive="${tmp_dir}/kurali-all.zip"

    info "正在下载更新..."

    # 方法2a: git clone（最可靠）
    if has_cmd git; then
        info "尝试 git clone..."
        if git clone --depth 1 -b "${KURALI_UPDATE_BRANCH}" "${KURALI_REPO_URL}.git" "${tmp_dir}/repo" 2>/dev/null; then
            local src_dir="${tmp_dir}/repo"
            _apply_files "$src_dir"
            rm -rf "$tmp_dir"
            echo "$(date -Iseconds) update_via_clone" >> "${KURALI_HOME}/logs/network.log" 2>/dev/null || true
            return 0
        fi
        warn "git clone 失败，尝试 zip 下载..."
    fi

    # 方法2b: 下载 zip
    local -a urls=(
        "${KURALI_REPO_URL}/-/archive/${KURALI_UPDATE_BRANCH}/kurali-all-${KURALI_UPDATE_BRANCH}.zip"
        "${KURALI_REPO_URL}/repository/archive/${KURALI_UPDATE_BRANCH}"
    )
    local download_ok=0
    for url in "${urls[@]}"; do
        if _fetch "$url" "$archive" 2>/dev/null && [[ -s "$archive" ]]; then
            download_ok=1
            break
        fi
    done

    if [[ $download_ok -eq 0 ]]; then
        rm -rf "$tmp_dir"
        err "下载失败。请手动更新："
        err "  git clone --depth 1 ${KURALI_REPO_URL}.git /tmp/kurali-update"
        err "  sudo cp -a /tmp/kurali-update/modules /tmp/kurali-update/config /tmp/kurali-update/kuraliAll.sh /var/lib/kuraliAll/"
        return 1
    fi

    info "正在解压..."
    local extract_dir="${tmp_dir}/extract"
    mkdir -p "$extract_dir"
    unzip -qo "$archive" -d "$extract_dir" 2>/dev/null || {
        # 回退: 尝试用 bsdtar
        has_cmd bsdtar && bsdtar -xf "$archive" -C "$extract_dir" 2>/dev/null || {
            rm -rf "$tmp_dir"
            die "解压失败"
        }
    }

    # 找到解压后的目录（可能是 kurali-all-main/ 或 kurali-all-<branch>/）
    local src_dir
    src_dir=$(find "$extract_dir" -maxdepth 2 -name "kuraliAll.sh" -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
    [[ -z "$src_dir" ]] && { rm -rf "$tmp_dir"; die "无法找到更新文件"; }

    _apply_files "$src_dir"

    rm -rf "$tmp_dir"
    echo "$(date -Iseconds) update_via_zip" >> "${KURALI_HOME}/logs/network.log" 2>/dev/null || true
}

# ─── 主命令：self-update ───
cmd_self_update() {
    echo -e "\n${C_BOLD}${KURALI_NAME} 自更新${C_RESET}"
    echo -e "  当前版本: ${C_GREEN}v${KURALI_VERSION}${C_RESET}"
    echo -e "  更新源:   ${KURALI_REPO_URL}"
    echo ""

    # 检查工具
    if ! has_cmd curl && ! has_cmd wget; then
        die "需要 curl 或 wget 来执行更新"
    fi

    info "正在检查最新版本..."

    # 获取远程版本
    local remote_ver
    remote_ver=$(_get_remote_version) || die "无法获取远程版本，请检查网络"

    echo -e "  远程版本: ${C_GREEN}v${remote_ver}${C_RESET}"

    # 比较版本号
    local need_update=0
    if _version_gt "$remote_ver" "$KURALI_VERSION"; then
        need_update=1
    else
        # 版本号相同，比较 commit hash
        local remote_hash="" local_hash=""
        remote_hash=$(_get_remote_commit)
        if [[ -n "$remote_hash" ]]; then
            # 获取本地最新 commit（如果在 git 仓库内）
            if [[ -d "${_K_DIR}/.git" ]] && has_cmd git; then
                local_hash=$(cd "$_K_DIR" && git log --oneline -1 2>/dev/null | awk '{print $1}')
            fi
            if [[ -n "$local_hash" && "$remote_hash" != "$local_hash" ]]; then
                echo -e "  本地 commit: ${C_GRAY}${local_hash}${C_RESET}"
                echo -e "  远程 commit: ${C_GREEN}${remote_hash}${C_RESET}"
                need_update=1
            fi
        fi
    fi

    if [[ $need_update -eq 0 ]]; then
        ok "已是最新版本 (v${KURALI_VERSION})"
        return 0
    fi

    echo ""
    echo -e "  ${C_YELLOW}发现新版本可用${C_RESET}"
    echo ""

    [[ "$NO_CONFIRM" -ne 1 ]] && {
        read -rp "$(echo -e "  ${C_GREEN}立即更新？[Y/n]: ${C_RESET}")" ans
        [[ "$ans" == "n" || "$ans" == "N" ]] && { info "已取消"; return 0; }
    }

    _apply_update

    local new_ver
    new_ver=$(grep '^KURALI_VERSION=' "${_K_DIR}/modules/core.mod" 2>/dev/null | head -1 | sed 's/.*"\(.*\)".*/\1/')

    echo ""
    echo -e "  ${C_GREEN}${C_BOLD}✓ 更新完成！${C_RESET}"
    echo -e "  v${KURALI_VERSION} → v${new_ver:-$remote_ver}"
    echo -e "\n  ${C_YELLOW}提示: 重新运行 kurali 命令以使用新版本${C_RESET}\n"
}

# ─── 网络管理命令 ───
cmd_network() {
    local subcmd="${1:-status}"
    case "$subcmd" in
        status)
            echo -e "\n${C_BOLD}联网状态:${C_RESET}"
            if check_network_consent; then
                echo -e "  许可: ${C_GREEN}已授权${C_RESET}"
                echo -e "  文件: ${_update_consent_file}"
            else
                echo -e "  许可: ${C_YELLOW}未授权${C_RESET}"
            fi
            if [[ -f "${KURALI_HOME}/logs/network.log" ]]; then
                echo -e "\n  ${C_BOLD}最近操作:${C_RESET}"
                tail -5 "${KURALI_HOME}/logs/network.log" 2>/dev/null | while IFS= read -r line; do
                    echo -e "  ${C_GRAY}${line}${C_RESET}"
                done
            fi
            echo ""
            ;;
        grant)
            _save_consent
            ok "已授予联网许可"
            ;;
        revoke)
            revoke_consent
            ;;
        *)
            die "用法: kurali network <status|grant|revoke>"
            ;;
    esac
}
