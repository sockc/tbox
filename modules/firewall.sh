#!/usr/bin/env bash

firewall_menu() {
    while true; do
        print_header "防火墙工具"
        cat <<'EOF'
 1. 安装/启用 UFW（占位）
 2. 放行端口（占位）
 3. 关闭端口（占位）
 4. 查看规则
 5. 关闭防火墙（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续接入 UFW 安装/启用逻辑" ;;
            2) info "后续接入放行端口逻辑" ;;
            3) info "后续接入关闭端口逻辑" ;;
            4)
                if cmd_exists ufw; then
                    ufw status verbose || true
                elif cmd_exists firewall-cmd; then
                    firewall-cmd --state 2>/dev/null || true
                    firewall-cmd --list-all 2>/dev/null || true
                else
                    warn "未检测到 UFW / firewalld"
                fi
                ;;
            5) info "后续接入关闭防火墙逻辑" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}
