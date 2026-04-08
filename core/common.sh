#!/usr/bin/env bash

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
info()  { printf '\033[32m[INFO]\033[0m %s\n' "$*"; }
warn()  { printf '\033[33m[WARN]\033[0m %s\n' "$*"; }
error() { printf '\033[31m[ERR ]\033[0m %s\n' "$*"; }

pause() {
    echo
    read -r -p "按回车继续..." _
}

cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

get_os_name() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${PRETTY_NAME:-Unknown}"
    else
        echo "Unknown"
    fi
}

get_arch() {
    uname -m 2>/dev/null || echo "unknown"
}

get_kernel() {
    uname -r 2>/dev/null || echo "unknown"
}

get_ipv4() {
    local ip
    ip=""
    if cmd_exists curl; then
        ip="$(curl -4 -fsSL --max-time 3 ip.sb 2>/dev/null || true)"
    elif cmd_exists wget; then
        ip="$(wget -qO- -T 3 ip.sb 2>/dev/null || true)"
    fi
    [ -n "$ip" ] && echo "$ip" || echo "N/A"
}

detect_docker_status() {
    if ! cmd_exists docker; then
        echo "未安装"
        return
    fi
    if systemctl is-active --quiet docker 2>/dev/null; then
        echo "运行中"
    else
        echo "已安装/未运行"
    fi
}

detect_firewall_status() {
    if cmd_exists ufw; then
        if ufw status 2>/dev/null | grep -qi "Status: active"; then
            echo "UFW:开启"
            return
        fi
        echo "UFW:关闭"
        return
    fi

    if cmd_exists firewall-cmd; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            echo "firewalld:开启"
            return
        fi
        echo "firewalld:关闭"
        return
    fi

    echo "未检测到"
}

print_header() {
    local title="${1:-tbox}"
    clear
    echo "=============== ${title} ==============="
    echo "系统     : $(get_os_name)"
    echo "架构     : $(get_arch)"
    echo "内核     : $(get_kernel)"
    echo "公网 IPv4: $(get_ipv4)"
    echo "Docker   : $(detect_docker_status)"
    echo "防火墙   : $(detect_firewall_status)"
    echo "========================================"
    echo
}

require_root_action() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        error "该操作需要 root 权限。请使用 sudo tbox 或 root 运行。"
        return 1
    fi
    return 0
}

fetch_url() {
    local url="$1"
    local out="$2"

    if cmd_exists curl; then
        curl -fsSL --connect-timeout 10 --retry 2 "$url" -o "$out"
    elif cmd_exists wget; then
        wget -qO "$out" "$url"
    else
        error "缺少 curl/wget"
        return 1
    fi
}
