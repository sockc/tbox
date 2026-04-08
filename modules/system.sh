#!/usr/bin/env bash

system_menu() {
    while true; do
        print_header "系统工具"
        cat <<'EOF'
 1. 系统更新（占位）
 2. 系统清理（占位）
 3. 时区设置（占位）
 4. BBR 管理（占位）
 5. 查看系统信息
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续接入系统更新逻辑" ;;
            2) info "后续接入系统清理逻辑" ;;
            3) info "后续接入时区设置逻辑" ;;
            4) info "后续接入 BBR 管理逻辑" ;;
            5)
                echo "系统 : $(get_os_name)"
                echo "架构 : $(get_arch)"
                echo "内核 : $(get_kernel)"
                echo "IPv4 : $(get_ipv4)"
                ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}
