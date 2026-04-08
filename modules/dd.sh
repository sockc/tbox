#!/usr/bin/env bash

dd_menu() {
    while true; do
        print_header "DD/重装工具"
        cat <<'EOF'
 1. 常用 DD 脚本（占位）
 2. 网络信息检查
 3. 引导修复工具（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续接入 DD 脚本集合" ;;
            2)
                if cmd_exists ip; then
                    ip addr
                    echo
                    ip route || true
                else
                    warn "系统缺少 ip 命令"
                fi
                ;;
            3) info "后续接入引导修复逻辑" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}
