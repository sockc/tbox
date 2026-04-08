#!/usr/bin/env bash

docker_menu() {
    while true; do
        print_header "Docker 工具"
        cat <<'EOF'
 1. 安装 Docker（占位）
 2. 安装 Docker Compose（占位）
 3. 查看容器
 4. 清理无用镜像/容器（占位）
 5. 常用容器脚本（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续接入 Docker 安装逻辑" ;;
            2) info "后续接入 Compose 安装逻辑" ;;
            3)
                if cmd_exists docker; then
                    docker ps -a || true
                else
                    warn "Docker 未安装"
                fi
                ;;
            4) info "后续接入 Docker 清理逻辑" ;;
            5) info "后续接入常用容器脚本逻辑" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}
