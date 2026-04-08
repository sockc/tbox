#!/usr/bin/env bash

get_ssh_service_name() {
    if systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then
        echo "sshd"
        return
    fi
    if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
        echo "ssh"
        return
    fi
    echo "ssh"
}

get_ssh_status() {
    local svc
    svc="$(get_ssh_service_name)"

    if ! command -v systemctl >/dev/null 2>&1; then
        echo "未知"
        return
    fi

    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo "运行中"
    else
        echo "未运行"
    fi
}

get_ssh_port() {
    local port
    if [ -f /etc/ssh/sshd_config ]; then
        port="$(grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | tail -n1 | awk '{print $2}')"
        [ -n "${port:-}" ] && echo "$port" || echo "22"
    else
        echo "22"
    fi
}

get_root_login_status() {
    local v
    if [ -f /etc/ssh/sshd_config ]; then
        v="$(grep -E '^[[:space:]]*PermitRootLogin[[:space:]]+' /etc/ssh/sshd_config 2>/dev/null | tail -n1 | awk '{print $2}')"
        case "${v:-}" in
            yes) echo "允许" ;;
            no) echo "禁止" ;;
            prohibit-password) echo "仅密钥" ;;
            forced-commands-only) echo "受限" ;;
            *) echo "默认" ;;
        esac
    else
        echo "未知"
    fi
}

get_password_auth_status() {
    local v
    if [ -f /etc/ssh/sshd_config ]; then
        v="$(grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+' /etc/ssh/sshd_config 2>/dev/null | tail -n1 | awk '{print $2}')"
        case "${v:-}" in
            yes) echo "开启" ;;
            no) echo "关闭" ;;
            *) echo "默认" ;;
        esac
    else
        echo "未知"
    fi
}

ssh_menu() {
    while true; do
        print_header "SSH 工具"
        cat <<EOF
 SSH 服务状态     : $(get_ssh_status)
 SSH 端口         : $(get_ssh_port)
 Root 登录        : $(get_root_login_status)
 密码登录         : $(get_password_auth_status)

 1. 查看 SSH 状态
 2. 查看 SSH 配置
 3. 修改 SSH 端口（占位）
 4. Root 登录管理（占位）
 5. 密码登录管理（占位）
 6. 公钥管理（占位）
 7. 重启 SSH 服务
 8. 查看 SSH 最近日志
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1)
                local svc
                svc="$(get_ssh_service_name)"
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl status "$svc" --no-pager -l || true
                else
                    warn "当前系统不支持 systemctl"
                fi
                ;;
            2)
                if [ -f /etc/ssh/sshd_config ]; then
                    sed -n '1,220p' /etc/ssh/sshd_config
                else
                    warn "/etc/ssh/sshd_config 不存在"
                fi
                ;;
            3)
                info "后续接入 SSH 端口修改逻辑"
                ;;
            4)
                info "后续接入 Root 登录管理逻辑"
                ;;
            5)
                info "后续接入密码登录管理逻辑"
                ;;
            6)
                info "后续接入 SSH 公钥管理逻辑"
                ;;
            7)
                require_root_action || { pause; continue; }
                svc="$(get_ssh_service_name)"
                systemctl restart "$svc" && info "SSH 服务已重启" || error "SSH 服务重启失败"
                ;;
            8)
                local svc
                svc="$(get_ssh_service_name)"
                if command -v journalctl >/dev/null 2>&1; then
                    journalctl -u "$svc" -n 50 --no-pager || true
                else
                    warn "系统缺少 journalctl"
                fi
                ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}
