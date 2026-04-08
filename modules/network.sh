#!/usr/bin/env bash

network_menu() {
    while true; do
        print_header "网络工具"
        cat <<'EOF'
 1. IP 信息查询
 2. 端口占用查询
 3. 网速测试（占位）
 4. 路由追踪（占位）
 5. DNS 测试（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1)
                echo "公网 IPv4: $(get_ipv4)"
                ;;
            2)
                if cmd_exists ss; then
                    ss -tulpn || true
                else
                    warn "系统缺少 ss 命令"
                fi
                ;;
            3) info "后续接入测速逻辑" ;;
            4) info "后续接入 traceroute / mtr 逻辑" ;;
            5) info "后续接入 DNS 测试逻辑" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}
