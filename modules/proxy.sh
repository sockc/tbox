#!/usr/bin/env bash

proxy_menu() {
    while true; do
        print_header "代理工具"
        cat <<'EOF'
 1. Xray 管理（占位）
 2. Sing-box 管理（占位）
 3. Hysteria2 管理（占位）
 4. Mihomo 管理（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续接入 Xray 模块" ;;
            2) info "后续接入 Sing-box 模块" ;;
            3) info "后续接入 Hysteria2 模块" ;;
            4) info "后续接入 Mihomo 模块" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}
