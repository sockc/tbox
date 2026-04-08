#!/usr/bin/env bash

panel_menu() {
    while true; do
        print_header "面板工具"
        cat <<'EOF'
 1. x-ui（占位）
 2. s-ui（占位）
 3. 1Panel（占位）
 4. 宝塔（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续接入 x-ui 模块" ;;
            2) info "后续接入 s-ui 模块" ;;
            3) info "后续接入 1Panel 模块" ;;
            4) info "后续接入宝塔模块" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}
