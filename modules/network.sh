#!/usr/bin/env bash

get_ipv6() {
    local ip
    ip=""
    if cmd_exists curl; then
        ip="$(curl -6 -fsSL --max-time 4 ip.sb 2>/dev/null || true)"
    elif cmd_exists wget; then
        ip="$(wget -qO- -T 4 ip.sb 2>/dev/null || true)"
    fi
    [ -n "$ip" ] && echo "$ip" || echo "N/A"
}

get_default_interface_net() {
    ip route 2>/dev/null | awk '/default/ {print $5; exit}'
}

get_default_gateway_net() {
    ip route 2>/dev/null | awk '/default/ {print $3; exit}'
}

get_local_ip_list() {
    if cmd_exists ip; then
        ip -o addr show scope global 2>/dev/null | awk '{print $2 " -> " $4}'
    else
        echo "系统缺少 ip 命令"
    fi
}

get_dns_servers() {
    if [ -f /etc/resolv.conf ]; then
        awk '/^nameserver[[:space:]]+/ {print $2}' /etc/resolv.conf
    else
        echo "N/A"
    fi
}

show_network_summary() {
    echo "公网 IPv4      : $(get_ipv4)"
    echo "公网 IPv6      : $(get_ipv6)"
    echo "默认网卡       : $(get_default_interface_net)"
    echo "默认网关       : $(get_default_gateway_net)"
    echo
    echo "本机地址："
    get_local_ip_list || true
    echo
    echo "DNS 服务器："
    get_dns_servers || true
}

show_ip_info() {
    print_header "IP 信息"
    echo "公网 IPv4: $(get_ipv4)"
    echo "公网 IPv6: $(get_ipv6)"
    echo
    echo "本机地址："
    get_local_ip_list || true
}

show_interfaces_and_routes() {
    print_header "网卡与路由"
    if cmd_exists ip; then
        echo "===== 网卡地址 ====="
        ip addr || true
        echo
        echo "===== IPv4 路由 ====="
        ip route || true
        echo
        echo "===== IPv6 路由 ====="
        ip -6 route || true
    else
        warn "系统缺少 ip 命令"
    fi
}

show_dns_config() {
    print_header "DNS 配置"
    echo "===== /etc/resolv.conf ====="
    if [ -f /etc/resolv.conf ]; then
        sed -n '1,200p' /etc/resolv.conf
    else
        warn "/etc/resolv.conf 不存在"
    fi
    echo
    echo "===== 当前 DNS 服务器 ====="
    get_dns_servers || true
}

port_query_interactive() {
    local keyword port
    print_header "端口占用查询"
    cat <<'EOF'
 1. 查看全部监听端口
 2. 按端口号查询
 3. 按进程关键字查询
 0. 返回
EOF
    echo
    read -r -p "请输入选项: " sub

    case "$sub" in
        1)
            if cmd_exists ss; then
                ss -tulpn || true
            elif cmd_exists netstat; then
                netstat -tulpn || true
            else
                warn "系统缺少 ss / netstat"
            fi
            ;;
        2)
            read -r -p "请输入端口号: " port
            if [[ ! "${port:-}" =~ ^[0-9]+$ ]]; then
                error "端口格式无效"
                return 1
            fi

            if cmd_exists ss; then
                ss -tulpn | awk -v p=":${port}" 'NR==1 || index($5,p)>0'
            elif cmd_exists netstat; then
                netstat -tulpn | awk -v p=":${port}" 'NR<=2 || index($4,p)>0'
            else
                warn "系统缺少 ss / netstat"
            fi
            ;;
        3)
            read -r -p "请输入进程关键字: " keyword
            if [ -z "${keyword:-}" ]; then
                warn "关键字不能为空"
                return 1
            fi

            if cmd_exists ss; then
                ss -tulpn | grep -i --color=auto "$keyword" || warn "未找到匹配项"
            elif cmd_exists netstat; then
                netstat -tulpn | grep -i --color=auto "$keyword" || warn "未找到匹配项"
            else
                warn "系统缺少 ss / netstat"
            fi
            ;;
        0)
            return 0
            ;;
        *)
            warn "无效选项"
            ;;
    esac
}

ping_test_interactive() {
    local host count
    print_header "连通性测试"
    read -r -p "请输入目标地址或域名 [默认 1.1.1.1]: " host
    host="${host:-1.1.1.1}"
    read -r -p "请输入测试次数 [默认 4]: " count
    count="${count:-4}"

    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        error "次数格式无效"
        return 1
    fi

    if ! cmd_exists ping; then
        error "系统缺少 ping 命令"
        return 1
    fi

    ping -c "$count" "$host"
}

trace_route_interactive() {
    local host
    print_header "路由追踪"
    read -r -p "请输入目标地址或域名 [默认 1.1.1.1]: " host
    host="${host:-1.1.1.1}"

    if cmd_exists mtr; then
        mtr -rwzc 10 "$host"
        return 0
    fi

    if cmd_exists traceroute; then
        traceroute "$host"
        return 0
    fi

    if cmd_exists tracepath; then
        tracepath "$host"
        return 0
    fi

    warn "未检测到 mtr / traceroute / tracepath"
    warn "Debian/Ubuntu 可安装: apt-get install -y mtr-tiny traceroute"
    warn "RHEL/Alma/Rocky 可安装: dnf install -y mtr traceroute"
    return 1
}

dns_lookup_interactive() {
    local domain server
    print_header "DNS 测试"
    read -r -p "请输入要解析的域名 [默认 google.com]: " domain
    domain="${domain:-google.com}"
    read -r -p "指定 DNS 服务器（可留空）: " server

    echo "目标域名: $domain"
    [ -n "${server:-}" ] && echo "指定 DNS: $server"
    echo

    if cmd_exists dig; then
        if [ -n "${server:-}" ]; then
            dig @"$server" "$domain" +short
            echo
            dig @"$server" "$domain"
        else
            dig "$domain" +short
            echo
            dig "$domain"
        fi
        return 0
    fi

    if cmd_exists nslookup; then
        if [ -n "${server:-}" ]; then
            nslookup "$domain" "$server"
        else
            nslookup "$domain"
        fi
        return 0
    fi

    if cmd_exists getent; then
        getent ahosts "$domain" || true
        return 0
    fi

    warn "未检测到 dig / nslookup / getent"
    warn "Debian/Ubuntu 可安装: apt-get install -y dnsutils"
    warn "RHEL/Alma/Rocky 可安装: dnf install -y bind-utils"
    return 1
}

speed_test_interactive() {
    print_header "网速测试"

    if cmd_exists speedtest; then
        speedtest
        return 0
    fi

    if cmd_exists speedtest-cli; then
        speedtest-cli
        return 0
    fi

    if cmd_exists fast; then
        fast
        return 0
    fi

    warn "未检测到 speedtest / speedtest-cli / fast"
    warn "建议先安装官方测速工具后再使用此菜单。"
    echo
    echo "常见安装方式："
    echo "Debian/Ubuntu:"
    echo "  apt-get update && apt-get install -y speedtest-cli"
    echo
    echo "RHEL/Alma/Rocky:"
    echo "  dnf install -y speedtest-cli"
    echo
    echo "或自行安装 Ookla Speedtest CLI。"
    return 1
}

network_menu() {
    local choice
    while true; do
        print_header "网络工具"
        cat <<EOF
 公网 IPv4        : $(get_ipv4)
 公网 IPv6        : $(get_ipv6)
 默认网卡         : $(get_default_interface_net)
 默认网关         : $(get_default_gateway_net)

 1. 查看网络摘要
 2. 查看 IP 信息
 3. 查看网卡与路由
 4. 端口占用查询
 5. 连通性测试（Ping）
 6. 路由追踪
 7. DNS 测试
 8. 查看 DNS 配置
 9. 网速测试
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice

        case "$choice" in
            1)
                show_network_summary
                ;;
            2)
                show_ip_info
                ;;
            3)
                show_interfaces_and_routes
                ;;
            4)
                port_query_interactive
                ;;
            5)
                ping_test_interactive
                ;;
            6)
                trace_route_interactive
                ;;
            7)
                dns_lookup_interactive
                ;;
            8)
                show_dns_config
                ;;
            9)
                speed_test_interactive
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
