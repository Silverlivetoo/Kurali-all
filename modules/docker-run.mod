#!/usr/bin/env bash
# docker-run.mod — Docker/Podman 容器兜底

# ─── 检测容器运行时 ───
CONTAINER_RT=""  # docker 或 podman

detect_container_rt() {
    if has_cmd docker && docker info &>/dev/null 2>&1; then
        CONTAINER_RT="docker"
    elif has_cmd podman && podman info &>/dev/null 2>&1; then
        CONTAINER_RT="podman"
    else
        return 1
    fi
    debug "容器运行时: $CONTAINER_RT"
    return 0
}

# ─── 选择基础镜像（根据源格式 + 发行版）───
_select_base_image() {
    local file="$1" format="$2"
    case "$format" in
        rpm)    echo "fedora:latest" ;;
        pacman) echo "archlinux:latest" ;;
        apk)    echo "alpine:latest" ;;
        deb)
            # 尝试匹配当前发行版
            if [[ -f /etc/os-release ]]; then
                local id; id=$(. /etc/os-release && echo "${ID:-ubuntu}")
                case "$id" in
                    ubuntu|pop|elementary|linuxmint) echo "ubuntu:22.04" ;;
                    debian|kali)                     echo "debian:stable" ;;
                    *)                               echo "ubuntu:22.04" ;;
                esac
            else
                echo "ubuntu:22.04"
            fi
            ;;
        *)      echo "ubuntu:22.04" ;;
    esac
}

# ─── 生成安装脚本（容器内自动安装包）───
_gen_install_script() {
    local filename="$1" format="$2"
    case "$format" in
        deb)
            cat << 'INST'
apt-get update -qq && apt-get install -y -qq /tmp/pkg/*.deb || dpkg -i /tmp/pkg/*.deb || true
apt-get install -f -y -qq 2>/dev/null || true
INST
            ;;
        rpm)
            cat << 'INST'
rpm -ivh --nodeps /tmp/pkg/*.rpm 2>/dev/null || yum install -y /tmp/pkg/*.rpm 2>/dev/null || dnf install -y /tmp/pkg/*.rpm 2>/dev/null || true
INST
            ;;
        pacman)
            cat << 'INST'
pacman -Sy --noconfirm 2>/dev/null || true
pacman -U --noconfirm /tmp/pkg/*.pkg.tar.* 2>/dev/null || true
INST
            ;;
        apk)
            cat << 'INST'
apk add --allow-untrusted /tmp/pkg/*.apk 2>/dev/null || true
INST
            ;;
        appimage)
            cat << 'INST'
cp /tmp/pkg/*.AppImage /usr/local/bin/ 2>/dev/null || cp /tmp/pkg/*appimage /usr/local/bin/ 2>/dev/null
chmod +x /usr/local/bin/*.AppImage 2>/dev/null || chmod +x /usr/local/bin/*appimage 2>/dev/null || true
INST
            ;;
        tar|zip)
            cat << 'INST'
cp -a /tmp/pkg/* / 2>/dev/null || true
INST
            ;;
        *)
            cat << 'INST'
cp -a /tmp/pkg/* / 2>/dev/null || true
INST
            ;;
    esac
}

# ─── Docker/Podman 安装 ───
docker_install() {
    local file="$1" name="$2"
    [[ -z "$name" ]] && name="kurali-$(basename "$file" | sed 's/[^a-zA-Z0-9._-]/-/g')"
    info "容器安装: $name"

    detect_container_rt || die "Docker 和 Podman 都不可用"

    local filename; filename=$(basename "$file")
    local format; format=$(detect_format "$filename")
    local base; base=$(_select_base_image "$file" "$format")

    local ddir="${PKG_DIR}/${name}/docker"
    mkdir -p "$ddir"
    cp "$file" "$ddir/"

    info "运行时: ${CONTAINER_RT}  基础镜像: ${base}"

    # 生成安装脚本
    _gen_install_script "$filename" "$format" > "${ddir}/install.sh"
    chmod +x "${ddir}/install.sh"

    # 生成 Dockerfile
    cat > "${ddir}/Dockerfile" << EOF
FROM ${base}
COPY $(basename "$file") /tmp/pkg/
COPY install.sh /tmp/install.sh
RUN chmod +x /tmp/install.sh && /tmp/install.sh
WORKDIR /root
CMD ["/bin/bash"]
EOF

    # 构建镜像
    ${CONTAINER_RT} build -t "kurali/${name}" "$ddir" 2>/dev/null && \
        ok "镜像: kurali/${name}" || {
            err "构建失败"
            # 备用：不解压，直接运行基础镜像挂载包
            warn "回退到挂载模式（不安装，直接挂载包目录）"
            _gen_mount_run "$file" "$name" "$base" "$ddir"
            return $?
        }

    # 生成运行脚本
    local script="${PKG_DIR}/${name}/run.sh"
    cat > "$script" << EOF
#!/bin/bash
# KuraliAll 容器运行: ${name}
${CONTAINER_RT} run -it --rm kurali/${name} "\$@"
EOF
    chmod +x "$script"

    # 桌面集成
    has_cmd install_desktop_entry 2>/dev/null && \
        install_desktop_entry "$name" "$name (容器)" "$script" "" 2>/dev/null || true

    ok "容器安装完成: $name"
    info "运行: ${script}"
}

# ─── 挂载模式（构建失败的兜底）───
_gen_mount_run() {
    local file="$1" name="$2" base="$3" ddir="$4"

    # 先解压包到本地目录
    local extract_dir="${ddir}/rootfs"
    mkdir -p "$extract_dir"
    extract_pkg "$file" "$(detect_format "$(basename "$file")")" "$extract_dir" 2>/dev/null || true

    local script="${PKG_DIR}/${name}/run.sh"
    cat > "$script" << EOF
#!/bin/bash
# KuraliAll 容器挂载运行: ${name}
# 包文件挂载到容器内，不安装到镜像
${CONTAINER_RT} run -it --rm -v "${extract_dir}:/mnt/pkg:ro" ${base} /bin/bash -c '
export PATH="/mnt/pkg/usr/bin:/mnt/pkg/bin:/mnt/pkg/usr/local/bin:\$PATH"
export LD_LIBRARY_PATH="/mnt/pkg/usr/lib:/mnt/pkg/usr/lib64:/mnt/pkg/lib:\$LD_LIBRARY_PATH"
echo "=== KuraliAll 容器 (${name}) ==="
echo "包已挂载到 /mnt/pkg"
echo "PATH/LD_LIBRARY_PATH 已配置"
exec /bin/bash
'
EOF
    chmod +x "$script"

    ok "容器挂载运行: $name（挂载模式）"
    info "运行: ${script}"
}

# ─── Docker/Podman 兜底交互 ───
docker_fallback() {
    local file="$1" name="$2"
    echo -e "\n${C_BOLD}安装失败，可选操作:${C_RESET}"
    echo "  1) 容器运行 (${CONTAINER_RT:-检测中...})"
    echo "  2) RAM 模式（内存运行，不安装）"
    echo "  3) 放弃"
    read -rp "$(echo -e "${C_YELLOW}[?]${C_RESET} 选择 [1-3]: ")" ch
    case "$ch" in
        1)
            detect_container_rt || { err "Docker/Podman 不可用"; return 1; }
            docker_install "$file" "$name"
            ;;
        2)
            run_in_ram "$file"
            ;;
        *) info "放弃" ;;
    esac
}
