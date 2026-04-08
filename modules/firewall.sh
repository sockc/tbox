#!/usr/bin/env bash

get_ssh_port_for_firewall() {
    local port

    if [ -f /etc/ssh/sshd_config.d/01-tbox.conf ]; then
        port="$(grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config.d/01-tbox.conf 2>/dev/null | awk '{print $2}' | tail -n1)"
        [ -n "${port:-}" ] && { echo "$port"; return; }
    fi

    if [ -f /etc/ssh/sshd_config ]; then
        port="$(grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -n1)"
        [ -n "${port:-}" ] && { echo "$port"; return; }
    fi

    if cmd_exists ss; then
        port="$(ss -tlnp 2>/dev/null | awk '/sshd/ {sub(/.*:/,"",$4); print $4; exit}')"
        [ -n "${port:-}" ] && { echo "$port"; return; }
    fi

    echo "22"
}

get_pkg_manager() {
    if cmd_exists apt-get; then
        echo "apt"
    elif cmd_exists dnf; then
        echo "dnf"
    elif cmd_exists yum; then
        echo "yum"
    elif cmd_exists apk; then
        echo "apk"
    else
        echo ""
    fi
}

detect_firewall_backend() {
    if cmd_exists ufw; then
        echo "ufw"
        return
    fi

    if cmd_exists firewall-cmd || systemctl list-unit-files 2>/dev/null | grep -q '^firewalld\.service'; then
        echo "firewalld"
        return
    fi

    if cmd_exists iptables; then
        echo "iptables"
        return
    fi

    echo "none"
}

get_firewall_status_text() {
    local backend
    backend="$(detect_firewall_backend)"

    case "$backend" in
        ufw)
            if ufw status 2>/dev/null | grep -qi "Status: active"; then
                echo "UFW:开启"
            else
                echo "UFW:关闭"
            fi
            ;;
        firewalld)
            if systemctl is-active --quiet firewalld 2>/dev/null; then
                echo "firewalld:开启"
            else
                echo "firewalld:关闭"
            fi
            ;;
        iptables)
            echo "iptables:已检测到"
            ;;
        *)
            echo "未安装"
            ;;
    esac
}

validate_fw_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

validate_fw_proto() {
    local proto="${1,,}"
    [ "$proto" = "tcp" ] || [ "$proto" = "udp" ]
}

install_firewall_backend() {
    require_root_action || return 1

    local backend pkgm
    backend="$(detect_firewall_backend)"

    if [ "$backend" != "none" ]; then
        info "已检测到防火墙后端: $backend"
        return 0
    fi

    pkgm="$(get_pkg_manager)"
    if [ -z "$pkgm" ]; then
        error "未识别包管理器，无法自动安装防火墙。"
        return 1
    fi

    print_header "安装防火墙"
    cat <<'EOF'
未检测到防火墙，选择要安装的后端：

 1. UFW
 2. firewalld
 0. 返回
EOF
    echo
    read -r -p "请输入选项: " choice

    case "$choice" in
        1)
            case "$pkgm" in
                apt)
                    apt-get update && apt-get install -y ufw
                    ;;
                dnf)
                    dnf install -y ufw
                    ;;
                yum)
                    yum install -y epel-release || true
                    yum install -y ufw
                    ;;
                apk)
                    apk add ufw
                    ;;
                *)
                    error "当前系统无法自动安装 UFW"
                    return 1
                    ;;
            esac
            ;;
        2)
            case "$pkgm" in
                apt)
                    apt-get update && apt-get install -y firewalld
                    ;;
                dnf)
                    dnf install -y firewalld
                    ;;
                yum)
                    yum install -y firewalld
                    ;;
                apk)
                    error "Alpine 通常不建议这样装 firewalld"
                    return 1
                    ;;
                *)
                    error "当前系统无法自动安装 firewalld"
                    return 1
                    ;;
            esac
            ;;
        0)
            return 0
            ;;
        *)
            warn "无效选项"
            return 1
            ;;
    esac

    info "安装完成。"
}

ensure_firewalld_running() {
    require_root_action || return 1

    if ! cmd_exists systemctl; then
        error "系统不支持 systemctl，无法管理 firewalld"
        return 1
    fi

    systemctl enable --now firewalld
}

allow_port_backend() {
    local port="$1"
    local proto="$2"
    local backend

    require_root_action || return 1

    if ! validate_fw_port "$port"; then
        error "端口无效: $port"
        return 1
    fi

    if ! validate_fw_proto "$proto"; then
        error "协议无效: $proto"
        return 1
    fi

    backend="$(detect_firewall_backend)"

    case "$backend" in
        ufw)
            ufw allow "${port}/${proto}"
            ;;
        firewalld)
            ensure_firewalld_running || return 1
            firewall-cmd --permanent --add-port="${port}/${proto}"
            firewall-cmd --reload
            ;;
        iptables)
            iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT
            if [[ "$proto" = "tcp" ]] && cmd_exists ip6tables; then
                ip6tables -C INPUT -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1 || ip6tables -I INPUT -p "$proto" --dport "$port" -j ACCEPT
            fi
            warn "iptables 规则已添加，但可能不会持久保存。"
            ;;
        *)
            error "未检测到可用防火墙后端。"
            return 1
            ;;
    esac

    info "已放行 ${proto^^} 端口 ${port}"
}

deny_port_backend() {
    local port="$1"
    local proto="$2"
    local backend

    require_root_action || return 1

    if ! validate_fw_port "$port"; then
        error "端口无效: $port"
        return 1
    fi

    if ! validate_fw_proto "$proto"; then
        error "协议无效: $proto"
        return 1
    fi

    backend="$(detect_firewall_backend)"

    case "$backend" in
        ufw)
            ufw delete allow "${port}/${proto}" || ufw delete allow "$port" || true
            ;;
        firewalld)
            ensure_firewalld_running || return 1
            firewall-cmd --permanent --remove-port="${port}/${proto}" || true
            firewall-cmd --reload
            ;;
        iptables)
            while iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1; do
                iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT || break
            done
            if [[ "$proto" = "tcp" ]] && cmd_exists ip6tables; then
                while ip6tables -C INPUT -p "$proto" --dport "$port" -j ACCEPT >/dev/null 2>&1; do
                    ip6tables -D INPUT -p "$proto" --dport "$port" -j ACCEPT || break
                done
            fi
            warn "iptables 放行规则已尝试删除。"
            ;;
        *)
            error "未检测到可用防火墙后端。"
            return 1
            ;;
    esac

    info "已关闭 ${proto^^} 端口 ${port}"
}

enable_firewall_interactive() {
    require_root_action || return 1

    local backend ssh_port
    install_firewall_backend || return 1
    backend="$(detect_firewall_backend)"
    ssh_port="$(get_ssh_port_for_firewall)"

    case "$backend" in
        ufw)
            info "当前 SSH 端口: ${ssh_port}"
            ufw allow "${ssh_port}/tcp"
            ufw --force enable
            info "UFW 已启用，并已放行 SSH 端口 ${ssh_port}"
            ;;
        firewalld)
            ensure_firewalld_running || return 1
            firewall-cmd --permanent --add-port="${ssh_port}/tcp"
            firewall-cmd --reload
            info "firewalld 已启用，并已放行 SSH 端口 ${ssh_port}"
            ;;
        iptables)
            warn "当前仅检测到 iptables。"
            warn "为避免误锁自己，这里不自动切默认拒绝策略。"
            warn "你可以先使用“放行端口”功能添加规则。"
            ;;
        *)
            error "未检测到可用防火墙后端。"
            return 1
            ;;
    esac
}

disable_firewall_interactive() {
    require_root_action || return 1

    local backend
    backend="$(detect_firewall_backend)"

    warn "关闭防火墙可能导致服务器暴露在公网。"
    read -r -p "确认继续？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *)
            info "已取消。"
            return 0
            ;;
    esac

    case "$backend" in
        ufw)
            ufw --force disable
            info "UFW 已关闭"
            ;;
        firewalld)
            if cmd_exists systemctl; then
                systemctl disable --now firewalld
                info "firewalld 已关闭"
            else
                error "系统不支持 systemctl，无法关闭 firewalld"
                return 1
            fi
            ;;
        iptables)
            warn "检测到 iptables。"
            warn "将尝试清空 INPUT/FORWARD/OUTPUT 规则并恢复 ACCEPT 策略。"
            read -r -p "再次确认？[y/N]: " ans2
            case "$ans2" in
                y|Y|yes|YES)
                    iptables -P INPUT ACCEPT || true
                    iptables -P FORWARD ACCEPT || true
                    iptables -P OUTPUT ACCEPT || true
                    iptables -F || true
                    if cmd_exists ip6tables; then
                        ip6tables -P INPUT ACCEPT || true
                        ip6tables -P FORWARD ACCEPT || true
                        ip6tables -P OUTPUT ACCEPT || true
                        ip6tables -F || true
                    fi
                    warn "iptables 规则已清空。若系统有持久化服务，下次重启后可能恢复。"
                    ;;
                *)
                    info "已取消。"
                    ;;
            esac
            ;;
        *)
            warn "未检测到可用防火墙后端。"
            ;;
    esac
}

show_firewall_rules() {
    local backend
    backend="$(detect_firewall_backend)"

    echo "当前后端 : $backend"
    echo "当前状态 : $(get_firewall_status_text)"
    echo

    case "$backend" in
        ufw)
            ufw status verbose || true
            ;;
        firewalld)
            if systemctl is-active --quiet firewalld 2>/dev/null; then
                firewall-cmd --list-all || true
            else
                warn "firewalld 当前未运行"
            fi
            ;;
        iptables)
            iptables -S || true
            if cmd_exists ip6tables; then
                echo
                echo "----- IPv6 -----"
                ip6tables -S || true
            fi
            ;;
        *)
            warn "未检测到可用防火墙后端。"
            ;;
    esac
}

open_port_interactive() {
    local port proto
    require_root_action || return 1

    print_header "放行端口"
    read -r -p "请输入端口: " port
    read -r -p "请输入协议 [tcp/udp，默认 tcp]: " proto
    proto="${proto:-tcp}"
    proto="${proto,,}"

    if ! validate_fw_port "$port"; then
        error "端口无效。"
        return 1
    fi

    if ! validate_fw_proto "$proto"; then
        error "协议只能是 tcp 或 udp。"
        return 1
    fi

    allow_port_backend "$port" "$proto"
}

close_port_interactive() {
    local port proto
    require_root_action || return 1

    print_header "关闭端口"
    read -r -p "请输入端口: " port
    read -r -p "请输入协议 [tcp/udp，默认 tcp]: " proto
    proto="${proto:-tcp}"
    proto="${proto,,}"

    if ! validate_fw_port "$port"; then
        error "端口无效。"
        return 1
    fi

    if ! validate_fw_proto "$proto"; then
        error "协议只能是 tcp 或 udp。"
        return 1
    fi

    deny_port_backend "$port" "$proto"
}

firewall_menu() {
    local choice

    while true; do
        print_header "防火墙工具"
        cat <<EOF
 当前后端         : $(detect_firewall_backend)
 当前状态         : $(get_firewall_status_text)
 当前 SSH 端口    : $(get_ssh_port_for_firewall)

 1. 安装/启用防火墙
 2. 放行端口
 3. 关闭端口
 4. 查看规则
 5. 关闭防火墙
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice

        case "$choice" in
            1)
                enable_firewall_interactive
                ;;
            2)
                open_port_interactive
                ;;
            3)
                close_port_interactive
                ;;
            4)
                show_firewall_rules
                ;;
            5)
                disable_firewall_interactive
                ;;
            0)
                return
                ;;
            *)
                warn "无效选项"
                ;;
        esac
        pause
    done
}
