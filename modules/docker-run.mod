#!/usr/bin/env bash
# docker-run.mod — Docker 容器兜底

check_docker() { has_cmd docker && docker info &>/dev/null 2>&1; }

docker_install() {
    local file="$1" name="$2"
    [[ -z "$name" ]] && name="kurali-$(basename "$file" | sed 's/[^a-zA-Z0-9._-]/-/g')"
    info "Docker 安装: $name"
    check_docker || die "Docker 不可用"

    local ddir="${PKG_DIR}/${name}/docker"
    mkdir -p "$ddir"; cp "$file" "$ddir/"

    local base="ubuntu:22.04"
    case "$(basename "$file")" in *.rpm) base="fedora:latest";; *.pkg.*) base="archlinux:latest";; esac

    cat > "$ddir/Dockerfile" << EOF
FROM ${base}
COPY $(basename "$file") /tmp/pkg
CMD ["/bin/bash"]
EOF

    docker build -t "kurali/${name}" "$ddir" 2>/dev/null && ok "镜像: kurali/${name}" || { err "构建失败"; return 1; }

    local script="${PKG_DIR}/${name}/run.sh"
    echo '#!/bin/bash' > "$script"
    echo "docker run -it --rm kurali/${name} \"\$@\"" >> "$script"
    chmod +x "$script"

    has_cmd install_desktop_entry && install_desktop_entry "$name" "$name (Docker)" "$script" "" 2>/dev/null || true
    ok "Docker 安装完成: $name"
}

docker_fallback() {
    local file="$1" name="$2"
    echo -e "\n${C_BOLD}安装失败，可选操作:${C_RESET}"
    echo "  1) Docker 容器运行"
    echo "  2) 放弃"
    read -rp "$(echo -e "${C_YELLOW}[?]${C_RESET} 选择 [1-2]: ")" ch
    [[ "$ch" == "1" ]] && docker_install "$file" "$name"
}
