#!/usr/bin/env bash
# service.mod — 服务管理

manage_service() {
    local action="$1" svc="$2"
    [[ -z "$svc" ]] && die "用法: kurali boot <enable|disable|status> <服务名>"
    has_cmd systemctl || die "需要 systemd"

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
