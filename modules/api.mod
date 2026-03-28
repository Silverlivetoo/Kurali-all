#!/usr/bin/env bash
# api.mod — JSON API接口（WebUI使用）

_json_start() {
    local status="$1" message="$2"
    printf '{"status":"%s","message":"%s","timestamp":"%s"}' "$status" "$message" "$(date -Iseconds)"
}

_json_error() {
    _json_start "error" "$1"
    exit 1
}

_json_success() {
    _json_start "success" "$1"
}

_json_array() {
    local key="$1"
    local data="$2"
    printf '{"status":"success","%s":[%s],"timestamp":"%s"}' "$key" "$data" "$(date -Iseconds)"
}

_json_object() {
    local key="$1"
    local data="$2"
    printf '{"status":"success","%s":%s,"timestamp":"%s"}' "$key" "$data" "$(date -Iseconds)"
}

cmd_api() {
    local action="$1" arg="$2"
    
    case "$action" in
        list)
            _api_list
            ;;
        info)
            [[ -z "$arg" ]] && _json_error "需要包名"
            _api_info "$arg"
            ;;
        install)
            [[ -z "$arg" ]] && _json_error "需要包文件路径"
            _api_install "$arg"
            ;;
        remove)
            [[ -z "$arg" ]] && _json_error "需要包名"
            _api_remove "$arg"
            ;;
        deps)
            _api_deps "$arg"
            ;;
        search)
            [[ -z "$arg" ]] && _json_error "需要搜索关键词"
            _api_search "$arg"
            ;;
        native)
            [[ -z "$arg" ]] && _json_error "需要包名"
            _api_native "$arg"
            ;;
        pack)
            [[ -z "$arg" ]] && _json_error "需要文件路径"
            _api_pack "$arg"
            ;;
        *)
            _json_error "未知API操作: $action"
            ;;
    esac
}

_api_list() {
    local entries=()
    for dir in "$PKG_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local name; name=$(basename "$dir")
        local info_file="${dir}/${name}.info"
        local entry="{\"name\":\"$name\""
        
        if [[ -f "$info_file" ]]; then
            local ver fmt mode installed
            ver=$(grep "^version=" "$info_file" | cut -d= -f2)
            fmt=$(grep "^format=" "$info_file" | cut -d= -f2)
            mode=$(grep "^mode=" "$info_file" | cut -d= -f2)
            installed=$(grep "^installed=" "$info_file" | cut -d= -f2 | cut -dT -f1)
            entry="${entry},\"version\":\"${ver:-unknown}\",\"format\":\"${fmt:-unknown}\",\"mode\":\"${mode:-sandbox}\",\"installed\":\"${installed:-unknown}\""
            
            # 计算大小
            local size=0
            if [[ -d "${dir}/rootfs" ]]; then
                size=$(find "${dir}/rootfs" -type f -exec du -sb {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')
            fi
            entry="${entry},\"size\":${size:-0}"
        else
            entry="${entry},\"version\":\"unknown\",\"format\":\"unknown\",\"mode\":\"unknown\",\"installed\":\"unknown\",\"size\":0}"
        fi
        
        entries+=("$entry}")
    done
    
    if [[ ${#entries[@]} -eq 0 ]]; then
        _json_array "packages" ""
    else
        _json_array "packages" "${entries[*]}"
    fi
}

_api_info() {
    local name="$1"
    local info_file="${PKG_DIR}/${name}/${name}.info"
    [[ -f "$info_file" ]] || _json_error "包不存在: $name"
    
    local data="{\"name\":\"$name\""
    
    # 读取info文件，跳过重复的name字段
    while IFS='=' read -r key value; do
        # 跳过name字段，因为已经添加
        [[ "$key" == "name" ]] && continue
        data="${data},\"${key}\":\"${value}\""
    done < "$info_file"
    
    # 添加结束的}
    data="${data}}"
    
    # 读取files文件
    local files_file="${PKG_DIR}/${name}/${name}.files"
    if [[ -f "$files_file" ]]; then
        local files_count=$(wc -l < "$files_file")
        data="${data},\"file_count\":${files_count}"
        
        # 获取前10个文件并转换为JSON数组
        local files_json="["
        local line_count=0
        while read -r line && [[ $line_count -lt 10 ]]; do
            files_json="${files_json}\"$line\","
            line_count=$((line_count+1))
        done < "$files_file"
        # 删除最后一个逗号
        files_json="${files_json%,}]"
        data="${data},\"files\":${files_json}"
    fi
    
    # 调试输出
    #echo "DEBUG: data = $data" > /tmp/kurali-api-debug.log
    _json_object "package" "${data}"
}

_api_search() {
    local kw="$1"
    local results=()
    for dir in "$PKG_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local name; name=$(basename "$dir")
        if echo "$name" | grep -qi "$kw"; then
            local info_file="${dir}/${name}.info"
            local ver="unknown" fmt="unknown" mode="sandbox"
            if [[ -f "$info_file" ]]; then
                ver=$(grep "^version=" "$info_file" | cut -d= -f2)
                fmt=$(grep "^format=" "$info_file" | cut -d= -f2)
                mode=$(grep "^mode=" "$info_file" | cut -d= -f2)
            fi
            results+=("{\"name\":\"$name\",\"version\":\"$ver\",\"format\":\"$fmt\",\"mode\":\"$mode\"}")
        fi
    done
    
    if [[ ${#results[@]} -eq 0 ]]; then
        _json_array "results" ""
    else
        _json_array "results" "${results[*]}"
    fi
}

_api_native() {
    local pkg="$1"
    detect_distro 2>/dev/null || true
    
    if [[ -z "$DISTRO_MGR" ]]; then
        _json_error "无法检测发行版"
        return 1
    fi
    
    # 调用原生包管理器
    local output=$(eval "$DISTRO_INSTALL $pkg" 2>&1)
    if [[ $? -eq 0 ]]; then
        _json_success "原生安装成功: $pkg"
    else
        _json_error "原生安装失败: $output"
    fi
}

_api_pack() {
    local file="$1"
    [[ -f "$file" ]] || _json_error "文件不存在: $file"
    
    # 调用外部命令
    local output=$(kurali pack "$file" 2>&1)
    if [[ $? -eq 0 ]]; then
        # 提取输出文件名
        local pkg_file=$(echo "$output" | grep -o "打包完成:.*(.*)" | grep -o "[^ ]*-unknown.kurali" || echo "")
        if [[ -n "$pkg_file" ]]; then
            local out_size=$(du -sh "$pkg_file" 2>/dev/null | cut -f1)
            _json_success "打包完成: $pkg_file (${out_size})"
        else
            _json_success "打包完成"
        fi
    else
        _json_error "打包失败: $output"
    fi
}

_api_install() {
    local file="$1"
    [[ -f "$file" ]] || _json_error "文件不存在: $file"
    
    # 调用外部命令
    local output=$(kurali i "$file" 2>&1)
    if [[ $? -eq 0 ]]; then
        # 提取包名
        local pkg_name=$(echo "$output" | grep -o "安装完成:.*" | grep -o "([^()]*)" | sed 's/(\|)//g' || echo "")
        if [[ -n "$pkg_name" ]]; then
            _json_success "安装成功: $pkg_name"
        else
            _json_success "安装成功"
        fi
    else
        _json_error "安装失败: $output"
    fi
}
    if [[ $? -eq 0 ]]; then
        _json_success "安装成功: $file"
    else
        _json_error "安装失败: $output"
    fi
}

_api_remove() {
    local name="$1"
    
    # 调用外部命令
    local output=$(kurali r "$name" 2>&1)
    if [[ $? -eq 0 ]]; then
        _json_success "卸载成功: $name"
    else
        _json_error "卸载失败: $output"
    fi
}

_api_deps() {
    local target="$1"
    
    if [[ -z "$target" ]]; then
        # 系统依赖检查
        local deps=("libc.so" "libm.so" "libdl.so" "libpthread.so" "libz.so" "libssl.so")
        local results=()
        for lib in "${deps[@]}"; do
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
            results+=("{\"library\":\"$lib\",\"found\":$found}")
        done
        _json_array "system_dependencies" "${results[*]}"
    elif [[ -f "$target" ]]; then
        # 程序依赖检查
        local ft=$(file -b "$target" 2>/dev/null)
        if ! echo "$ft" | grep -qi "elf\|dynamically linked"; then
            _json_error "非动态链接文件: $ft"
        fi
        
        local results=()
        ldd "$target" 2>&1 | while read -r line; do
            if echo "$line" | grep -q "not found"; then
                results+=("{\"library\":\"$(echo "$line" | awk '{print $1}')\",\"found\":false,\"message\":\"$line\"}")
            elif echo "$line" | grep -q "=>"; then
                local lib=$(echo "$line" | awk '{print $1}')
                results+=("{\"library\":\"$lib\",\"found\":true,\"message\":\"$line\"}")
            fi
        done
        
        if [[ ${#results[@]} -eq 0 ]]; then
            _json_array "program_dependencies" ""
        else
            _json_array "program_dependencies" "${results[*]}"
        fi
    else
        _json_error "文件不存在: $target"
    fi
}