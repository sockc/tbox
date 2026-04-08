#!/usr/bin/env bash

custom_server_menu() {
    local choice
    while true; do
        print_header "自建脚本集合 / 服务器脚本"
        cat <<'EOF'
 1. VPS 初始化脚本（占位）
 2. 常用环境安装脚本（占位）
 3. 系统优化脚本（占位）
 4. 常用命令快捷入口（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续这里放 VPS 初始化脚本。" ;;
            2) info "后续这里放常用环境安装脚本。" ;;
            3) info "后续这里放系统优化脚本。" ;;
            4) info "后续这里放命令快捷入口脚本。" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}

custom_docker_menu() {
    local choice
    while true; do
        print_header "自建脚本集合 / Docker 脚本"
        cat <<'EOF'
 1. Docker 应用一键部署（占位）
 2. Docker 环境初始化（占位）
 3. Compose 项目模板（占位）
 4. 容器维护脚本（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续这里放 Docker 应用一键部署脚本。" ;;
            2) info "后续这里放 Docker 环境初始化脚本。" ;;
            3) info "后续这里放 Compose 项目模板脚本。" ;;
            4) info "后续这里放容器维护脚本。" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}

custom_proxy_menu() {
    local choice
    while true; do
        print_header "自建脚本集合 / 代理脚本"
        cat <<'EOF'
 1. Xray 系列脚本（占位）
 2. Sing-box 系列脚本（占位）
 3. Mihomo 系列脚本（占位）
 4. Hysteria 系列脚本（占位）
 5. 订阅/规则辅助脚本（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续这里放 Xray 系列自建脚本。" ;;
            2) info "后续这里放 Sing-box 系列自建脚本。" ;;
            3) info "后续这里放 Mihomo 系列自建脚本。" ;;
            4) info "后续这里放 Hysteria 系列自建脚本。" ;;
            5) info "后续这里放订阅/规则辅助脚本。" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}

custom_panel_menu() {
    local choice
    while true; do
        print_header "自建脚本集合 / 面板脚本"
        cat <<'EOF'
 1. x-ui / s-ui 类脚本（占位）
 2. Web 面板脚本（占位）
 3. Cloudflare 隧道辅助脚本（占位）
 4. 面板备份恢复脚本（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续这里放 x-ui / s-ui 类脚本。" ;;
            2) info "后续这里放 Web 面板类脚本。" ;;
            3) info "后续这里放 Cloudflare 隧道辅助脚本。" ;;
            4) info "后续这里放面板备份恢复脚本。" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}

custom_maint_menu() {
    local choice
    while true; do
        print_header "自建脚本集合 / 维护脚本"
        cat <<'EOF'
 1. 系统清理脚本（占位）
 2. 日志巡检脚本（占位）
 3. 健康检查脚本（占位）
 4. 备份任务脚本（占位）
 5. 一键修复类脚本（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续这里放系统清理脚本。" ;;
            2) info "后续这里放日志巡检脚本。" ;;
            3) info "后续这里放健康检查脚本。" ;;
            4) info "后续这里放备份任务脚本。" ;;
            5) info "后续这里放一键修复类脚本。" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}

custom_other_menu() {
    local choice
    while true; do
        print_header "自建脚本集合 / 其它脚本"
        cat <<'EOF'
 1. 临时测试脚本（占位）
 2. 实验性脚本（占位）
 3. 待整理脚本（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续这里放临时测试脚本。" ;;
            2) info "后续这里放实验性脚本。" ;;
            3) info "后续这里放待整理脚本。" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}

custom_menu() {
    local choice

    while true; do
        print_header "自建脚本集合"
        cat <<'EOF'
 1. 服务器脚本
 2. Docker 脚本
 3. 代理脚本
 4. 面板脚本
 5. 维护脚本
 6. 其它脚本
 7. 查看规划说明
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice

        case "$choice" in
            1) custom_server_menu ;;
            2) custom_docker_menu ;;
            3) custom_proxy_menu ;;
            4) custom_panel_menu ;;
            5) custom_maint_menu ;;
            6) custom_other_menu ;;
            7)
                cat <<'EOT'
这个菜单专门用于管理你自己构建的脚本集合。

当前分层：
- 服务器脚本
- Docker 脚本
- 代理脚本
- 面板脚本
- 维护脚本
- 其它脚本

建议后续规则：
1. 主菜单只保留大分类
2. 真正的脚本尽量放到这一层下面
3. 每个类别后续再逐步实装
4. 单个功能尽量单独文件，避免一个文件越来越臃肿
EOT
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
