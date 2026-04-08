#!/usr/bin/env bash

TBOX_SYSCTL_DIR="/etc/sysctl.d"
TBOX_BBR_CONF="${TBOX_SYSCTL_DIR}/99-tbox-bbr.conf"

get_pkg_manager_system() {
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

get_mem_info() {
    if [ -r /proc/meminfo ]; then
        awk '
            /^MemTotal:/ {t=$2}
            /^MemAvailable:/ {a=$2}
            END {
                if (t > 0) {
                    used=t-a
                    printf "总计 %.1fG / 可用 %.1fG / 已用 %.1fG", t/1024/1024, a/1024/1024, used/1024/1024
                } else {
                    print "N/A"
                }
            }
        ' /proc/meminfo
    else
        echo "N/A"
    fi
}

get_disk_info() {
    df -h / 2>/dev/null | awk 'NR==2 {printf "根分区 %s / 已用 %s / 可用 %s / 使用率 %s", $2, $3, $4, $5}'
}

get_cpu_load_info() {
    awk '{printf "1min %.2f / 5min %.2f / 15min %.2f", $1, $2, $3}' /proc/loadavg 2>/dev/null || echo "N/A"
}

get_uptime_info() {
    uptime -p 2>/dev/null || uptime 2>/dev/null || echo "N/A"
}

get_timezone_info() {
    if cmd_exists timedatectl; then
        timedatectl 2>/dev/null | awk -F': ' '/Time zone/ {print $2; exit}'
    elif [ -L /etc/localtime ]; then
        readlink /etc/localtime | sed 's#^.*/zoneinfo/##'
    elif [ -f /etc/timezone ]; then
        cat /etc/timezone
    else
        echo "N/A"
    fi
}

get_system_time_info() {
    date '+%Y-%m-%d %H:%M:%S %Z'
}

get_virtualization_info() {
    if cmd_exists systemd-detect-virt; then
        systemd-detect-virt 2>/dev/null || echo "none"
    else
        echo "unknown"
    fi
}

get_default_interface() {
    ip route 2>/dev/null | awk '/default/ {print $5; exit}'
}

get_default_gateway() {
    ip route 2>/dev/null | awk '/default/ {print $3; exit}'
}

get_local_ips() {
    ip -o addr show scope global 2>/dev/null | awk '{print $2 " -> " $4}'
}

show_system_summary() {
    cat <<EOF
系统          : $(get_os_name)
架构          : $(get_arch)
内核          : $(get_kernel)
虚拟化        : $(get_virtualization_info)
公网 IPv4     : $(get_ipv4)
运行时长      : $(get_uptime_info)
系统时间      : $(get_system_time_info)
时区          : $(get_timezone_info)
负载          : $(get_cpu_load_info)
内存          : $(get_mem_info)
磁盘          : $(get_disk_info)
默认网卡      : $(get_default_interface)
默认网关      : $(get_default_gateway)
EOF
    echo
    echo "本机 IP："
    get_local_ips || true
}

update_system_packages() {
    require_root_action || return 1

    local pm
    pm="$(get_pkg_manager_system)"

    case "$pm" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get -y upgrade
            ;;
        dnf)
            dnf -y upgrade --refresh
            ;;
        yum)
            yum -y update
            ;;
        apk)
            apk update
            apk upgrade
            ;;
        *)
            error "未识别包管理器，无法自动更新系统。"
            return 1
            ;;
    esac

    info "系统更新完成。"
}

clean_system_interactive() {
    require_root_action || return 1

    local pm
    pm="$(get_pkg_manager_system)"

    print_header "系统清理"
    cat <<'EOF'
将执行常见清理操作：
- 包缓存清理
- 无用依赖清理（支持的系统）
- journal 日志瘦身（如支持）
- 临时文件清理（仅 /tmp 超过 7 天）

EOF
    read -r -p "确认继续？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *)
            info "已取消。"
            return 0
            ;;
    esac

    case "$pm" in
        apt)
            apt-get -y autoremove || true
            apt-get -y autoclean || true
            apt-get -y clean || true
            ;;
        dnf)
            dnf -y autoremove || true
            dnf clean all || true
            ;;
        yum)
            yum -y autoremove || true
            yum clean all || true
            ;;
        apk)
            rm -rf /var/cache/apk/* 2>/dev/null || true
            ;;
        *)
            warn "未识别包管理器，跳过包管理器缓存清理。"
            ;;
    esac

    if cmd_exists journalctl; then
        journalctl --vacuum-time=7d >/dev/null 2>&1 || true
    fi

    find /tmp -xdev -type f -mtime +7 -delete 2>/dev/null || true
    find /tmp -xdev -type d -empty -mtime +7 -delete 2>/dev/null || true

    info "系统清理完成。"
}

set_timezone_interactive() {
    require_root_action || return 1

    local tz zonefile
    print_header "时区设置"
    echo "当前时区: $(get_timezone_info)"
    echo
    echo "常用示例："
    echo "  Asia/Shanghai"
    echo "  Asia/Taipei"
    echo "  Asia/Tokyo"
    echo "  America/Los_Angeles"
    echo "  Europe/London"
    echo
    read -r -p "请输入目标时区: " tz

    if [ -z "${tz:-}" ]; then
        warn "时区不能为空。"
        return 1
    fi

    zonefile="/usr/share/zoneinfo/${tz}"
    if [ ! -e "$zonefile" ]; then
        error "时区不存在: $tz"
        return 1
    fi

    if cmd_exists timedatectl; then
        timedatectl set-timezone "$tz"
    else
        ln -sf "$zonefile" /etc/localtime
        echo "$tz" > /etc/timezone 2>/dev/null || true
    fi

    info "时区已设置为: $tz"
    info "当前系统时间: $(get_system_time_info)"
}

get_current_qdisc() {
    sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown"
}

get_current_cc_algo() {
    sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown"
}

get_available_cc_algos() {
    sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "unknown"
}

kernel_supports_bbr() {
    get_available_cc_algos | tr ' ' '\n' | grep -qx "bbr"
}

bbr_enabled() {
    [ "$(get_current_cc_algo)" = "bbr" ]
}

show_bbr_status() {
    echo "当前队列算法      : $(get_current_qdisc)"
    echo "当前拥塞控制算法  : $(get_current_cc_algo)"
    echo "可用拥塞控制算法  : $(get_available_cc_algos)"
    if kernel_supports_bbr; then
        echo "内核 BBR 支持     : 支持"
    else
        echo "内核 BBR 支持     : 不支持"
    fi

    if bbr_enabled; then
        echo "当前 BBR 状态     : 已启用"
    else
        echo "当前 BBR 状态     : 未启用"
    fi
}

enable_bbr() {
    require_root_action || return 1

    if ! kernel_supports_bbr; then
        error "当前内核不支持 BBR。"
        warn "可先升级到较新的内核后再尝试。"
        return 1
    fi

    mkdir -p "$TBOX_SYSCTL_DIR"

    cat > "$TBOX_BBR_CONF" <<'EOF'
# Managed by tbox
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

    if cmd_exists sysctl; then
        sysctl --system >/dev/null 2>&1 || {
            error "sysctl 应用失败，请检查系统配置。"
            return 1
        }
    fi

    info "BBR 已启用。"
    show_bbr_status
}

disable_bbr() {
    require_root_action || return 1

    rm -f "$TBOX_BBR_CONF"

    mkdir -p "$TBOX_SYSCTL_DIR"
    cat > "$TBOX_BBR_CONF" <<'EOF'
# Managed by tbox
net.core.default_qdisc=fq_codel
net.ipv4.tcp_congestion_control=cubic
EOF

    if cmd_exists sysctl; then
        sysctl --system >/dev/null 2>&1 || {
            error "sysctl 应用失败，请手动检查。"
            return 1
        }
    fi

    info "已关闭 BBR，并切回 cubic。"
    show_bbr_status
}

bbr_menu() {
    local choice
    while true; do
        print_header "BBR 管理"
        show_bbr_status
        echo
        cat <<'EOF'
 1. 查看 BBR 状态
 2. 启用 BBR
 3. 关闭 BBR（切回 cubic）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1)
                show_bbr_status
                ;;
            2)
                enable_bbr
                ;;
            3)
                disable_bbr
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

system_menu() {
    local choice
    while true; do
        print_header "系统工具"
        cat <<EOF
 运行时长        : $(get_uptime_info)
 系统时间        : $(get_system_time_info)
 时区            : $(get_timezone_info)
 BBR             : $( [ "$(get_current_cc_algo)" = "bbr" ] && echo "已启用" || echo "未启用" )

 1. 查看系统信息
 2. 系统更新
 3. 系统清理
 4. 时区设置
 5. BBR 管理
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice

        case "$choice" in
            1)
                show_system_summary
                ;;
            2)
                update_system_packages
                ;;
            3)
                clean_system_interactive
                ;;
            4)
                set_timezone_interactive
                ;;
            5)
                bbr_menu
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
