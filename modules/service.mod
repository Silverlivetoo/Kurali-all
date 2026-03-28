#!/usr/bin/env bash
# service.mod — 服务管理（systemd / OpenRC / sysvinit / runit）

# ─── 检测 init 系统 ───
detect_init_system() {
    if has_cmd systemctl && systemctl --version &>/dev/null 2>&1; then
        echo "systemd"
    elif has_cmd rc-update || [[ -f /etc/init.d/rc ]]; then
        echo "openrc"
    elif has_cmd sv || [[ -d /etc/sv ]]; then
        echo "runit"
    elif [[ -d /etc/init.d && ! -f /etc/init.d/rc ]]; then
        echo "sysvinit"
    else
        echo "unknown"
    fi
}

# ─── 服务操作 ───
manage_service() {
    local action="$1" svc="$2"
    [[ -z "$svc" ]] && die "用法: kurali boot <enable|disable|status> <服务名>"

    local init; init=$(detect_init_system)
    debug "init 系统: $init"

    case "$init" in
        systemd)
            _svc_systemd "$action" "$svc"
            ;;
        openrc)
            _svc_openrc "$action" "$svc"
            ;;
        runit)
            _svc_runit "$action" "$svc"
            ;;
        sysvinit)
            _svc_sysvinit "$action" "$svc"
            ;;
        *)
            warn "未知 init 系统，尝试通用方法..."
            _svc_fallback "$action" "$svc"
            ;;
    esac
}

# ─── systemd ───
_svc_systemd() {
    local action="$1" svc="$2"
    case "$action" in
        enable)
            safe_sudo systemctl enable "$svc" 2>/dev/null && ok "已启用: $svc" || err "启用失败: $svc"
            ;;
        disable)
            danger_confirm "禁用服务自启: $svc ?"
            safe_sudo systemctl disable "$svc" 2>/dev/null && ok "已禁用: $svc" || err "禁用失败: $svc"
            ;;
        status)
            systemctl is-enabled "$svc" 2>/dev/null
            systemctl status "$svc" 2>/dev/null
            ;;
        *)
            die "未知操作: $action (enable/disable/status)"
            ;;
    esac
}

# ─── OpenRC ───
_svc_openrc() {
    local action="$1" svc="$2"
    case "$action" in
        enable)
            safe_sudo rc-update add "$svc" default 2>/dev/null && ok "已启用: $svc" || err "启用失败: $svc"
            ;;
        disable)
            danger_confirm "禁用服务自启: $svc ?"
            safe_sudo rc-update del "$svc" default 2>/dev/null && ok "已禁用: $svc" || err "禁用失败: $svc"
            ;;
        status)
            rc-status "$svc" 2>/dev/null || rc-service "$svc" status 2>/dev/null
            ;;
        *)
            die "未知操作: $action (enable/disable/status)"
            ;;
    esac
}

# ─── runit ───
_svc_runit() {
    local action="$1" svc="$2"
    case "$action" in
        enable)
            if [[ -d "/etc/sv/$svc" ]]; then
                safe_sudo ln -sf "/etc/sv/$svc" "/var/service/" 2>/dev/null && ok "已启用: $svc" || err "启用失败: $svc"
            else
                err "服务目录不存在: /etc/sv/$svc"
            fi
            ;;
        disable)
            danger_confirm "禁用服务自启: $svc ?"
            safe_sudo rm -f "/var/service/$svc" 2>/dev/null && ok "已禁用: $svc" || err "禁用失败: $svc"
            ;;
        status)
            sv status "$svc" 2>/dev/null || warn "服务状态不可用"
            ;;
        *)
            die "未知操作: $action (enable/disable/status)"
            ;;
    esac
}

# ─── sysvinit ───
_svc_sysvinit() {
    local action="$1" svc="$2"
    case "$action" in
        enable)
            if has_cmd chkconfig; then
                safe_sudo chkconfig "$svc" on 2>/dev/null && ok "已启用: $svc" || err "启用失败: $svc"
            elif has_cmd update-rc.d; then
                safe_sudo update-rc.d "$svc" defaults 2>/dev/null && ok "已启用: $svc" || err "启用失败: $svc"
            else
                err "需要 chkconfig 或 update-rc.d"
            fi
            ;;
        disable)
            danger_confirm "禁用服务自启: $svc ?"
            if has_cmd chkconfig; then
                safe_sudo chkconfig "$svc" off 2>/dev/null && ok "已禁用: $svc" || err "禁用失败: $svc"
            elif has_cmd update-rc.d; then
                safe_sudo update-rc.d "$svc" remove 2>/dev/null && ok "已禁用: $svc" || err "禁用失败: $svc"
            else
                err "需要 chkconfig 或 update-rc.d"
            fi
            ;;
        status)
            if [[ -f "/etc/init.d/$svc" ]]; then
                /etc/init.d/"$svc" status 2>/dev/null || service "$svc" status 2>/dev/null
            else
                warn "服务脚本不存在: /etc/init.d/$svc"
            fi
            ;;
        *)
            die "未知操作: $action (enable/disable/status)"
            ;;
    esac
}

# ─── 通用兜底 ───
_svc_fallback() {
    local action="$1" svc="$2"
    case "$action" in
        enable|disable)
            warn "无法自动管理自启，请手动操作"
            info "常见方法:"
            info "  systemd: systemctl $action $svc"
            info "  openrc:  rc-update $([ "$action" = "enable" ] && echo "add" || echo "del") $svc"
            info "  runit:   ln -s /etc/sv/$svc /var/service/"
            ;;
        status)
            # 尝试各种方法
            systemctl status "$svc" 2>/dev/null || \
            rc-service "$svc" status 2>/dev/null || \
            sv status "$svc" 2>/dev/null || \
            service "$svc" status 2>/dev/null || \
            warn "无法获取服务状态"
            ;;
    esac
}
