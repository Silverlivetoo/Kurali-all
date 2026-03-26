#!/usr/bin/env bash
# ram-run.mod — 内存运行模式

RAM_TMPDIR=""
RAM_MOUNTED=0

setup_ram() {
    local base=""
    [[ -d /dev/shm && -w /dev/shm ]] && base="/dev/shm"
    [[ -z "$base" && -n "$XDG_RUNTIME_DIR" && -d "$XDG_RUNTIME_DIR" ]] && base="$XDG_RUNTIME_DIR"
    [[ -z "$base" && -d "/run/user/$UID" && -w "/run/user/$UID" ]] && base="/run/user/$UID"
    [[ -z "$base" && -d /tmp ]] && { base="/tmp"; warn "/tmp 非 tmpfs, 安全性稍低"; }
    [[ -z "$base" ]] && die "无可用临时目录"

    RAM_TMPDIR="${base}/kurali-$$-$(date +%s)"
    mkdir -p "$RAM_TMPDIR" || die "创建 RAM 目录失败"
    RAM_MOUNTED=1
    trap cleanup_ram EXIT INT TERM
    ok "RAM 目录: $RAM_TMPDIR"
}

cleanup_ram() {
    if [[ "$RAM_MOUNTED" -eq 1 && -n "$RAM_TMPDIR" && -d "$RAM_TMPDIR" ]]; then
        rm -rf "$RAM_TMPDIR" 2>/dev/null
        RAM_MOUNTED=0
        RAM_TMPDIR=""
        debug "RAM 清理完成"
    fi
}

run_in_ram() {
    local file="$1"; [[ -f "$file" ]] || die "文件不存在: $file"
    setup_ram
    local pkg="${RAM_TMPDIR}/pkg"
    mkdir -p "$pkg"

    local fmt; fmt=$(detect_format "$(basename "$file")")

    if [[ "$fmt" == "appimage" ]]; then
        cp "$file" "$RAM_TMPDIR/"; chmod +x "$RAM_TMPDIR/$(basename "$file")"
        "$RAM_TMPDIR/$(basename "$file")"
        return $?
    fi

    extract_pkg "$file" "$fmt" "$pkg" || die "解压失败"
    flatten_extract "$pkg"

    export LD_LIBRARY_PATH="${pkg}/usr/lib:${pkg}/usr/lib64:${pkg}/lib:${pkg}/lib64:${LD_LIBRARY_PATH}"
    export PATH="${pkg}/usr/bin:${pkg}/bin:${pkg}/usr/local/bin:${pkg}:${PATH}"

    local exes; exes=$(find "$pkg" -maxdepth 3 -type f -executable 2>/dev/null | sort -u | head -20)

    if [[ -z "$exes" ]]; then
        warn "未找到可执行文件"
        info "进入 RAM shell, Ctrl+D 退出清理"
        (cd "$RAM_TMPDIR" && exec bash --norc)
        return 0
    fi

    echo -e "${C_BOLD}可用程序:${C_RESET}"
    local -a exe_arr=()
    local idx=0
    while IFS= read -r ex; do
        idx=$((idx+1)); exe_arr+=("$ex")
        printf "  ${C_CYAN}%d${C_RESET} %s\n" "$idx" "$(basename "$ex")"
    done <<< "$exes"

    read -rp "$(echo -e "${C_YELLOW}[?]${C_RESET} 编号运行 / 'shell' 进交互 [编号/shell]: ")" ch
    if [[ "$ch" == "shell" ]]; then
        info "RAM shell, Ctrl+D 退出清理"
        (cd "$RAM_TMPDIR" && exec bash --norc)
    elif [[ "$ch" -ge 1 && "$ch" -le "${#exe_arr[@]}" ]]; then
        "${exe_arr[$((ch-1))]}"
    else
        die "无效选择"
    fi
}
