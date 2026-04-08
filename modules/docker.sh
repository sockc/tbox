#!/usr/bin/env bash

TBOX_DOCKER_APP_DIR="/opt/docker-apps"

get_pkg_manager_docker() {
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

get_docker_service_name() {
    echo "docker"
}

docker_installed() {
    cmd_exists docker
}

docker_running() {
    local svc
    svc="$(get_docker_service_name)"

    if cmd_exists systemctl; then
        systemctl is-active --quiet "$svc" 2>/dev/null
        return $?
    fi

    pgrep -x dockerd >/dev/null 2>&1
}

compose_available() {
    docker compose version >/dev/null 2>&1 || cmd_exists docker-compose
}

get_docker_version_text() {
    if docker_installed; then
        docker --version 2>/dev/null || echo "已安装"
    else
        echo "未安装"
    fi
}

get_compose_version_text() {
    if docker compose version >/dev/null 2>&1; then
        docker compose version 2>/dev/null | head -n1
    elif cmd_exists docker-compose; then
        docker-compose --version 2>/dev/null | head -n1
    else
        echo "未安装"
    fi
}

get_docker_service_status_text() {
    if ! docker_installed; then
        echo "未安装"
        return
    fi

    if docker_running; then
        echo "运行中"
    else
        echo "未运行"
    fi
}

get_docker_root_dir() {
    if docker_installed; then
        docker info 2>/dev/null | awk -F': ' '/Docker Root Dir/ {print $2; exit}'
    fi
}

get_docker_storage_driver() {
    if docker_installed; then
        docker info 2>/dev/null | awk -F': ' '/Storage Driver/ {print $2; exit}'
    fi
}

get_docker_cgroup_driver() {
    if docker_installed; then
        docker info 2>/dev/null | awk -F': ' '/Cgroup Driver/ {print $2; exit}'
    fi
}

get_docker_counts_summary() {
    if ! docker_installed; then
        echo "容器 0 / 镜像 0 / 网络 0 / 卷 0"
        return
    fi

    local c i n v
    c="$(docker ps -aq 2>/dev/null | wc -l | awk '{print $1}')"
    i="$(docker images -q 2>/dev/null | sort -u | wc -l | awk '{print $1}')"
    n="$(docker network ls -q 2>/dev/null | wc -l | awk '{print $1}')"
    v="$(docker volume ls -q 2>/dev/null | wc -l | awk '{print $1}')"

    echo "容器 ${c} / 镜像 ${i} / 网络 ${n} / 卷 ${v}"
}

show_docker_summary() {
    cat <<EOF
Docker            : $(get_docker_version_text)
Compose           : $(get_compose_version_text)
服务状态          : $(get_docker_service_status_text)
资源统计          : $(get_docker_counts_summary)
Docker Root Dir   : $(get_docker_root_dir)
Storage Driver    : $(get_docker_storage_driver)
Cgroup Driver     : $(get_docker_cgroup_driver)
应用目录          : ${TBOX_DOCKER_APP_DIR}
EOF
}

ensure_docker_installed() {
    if ! docker_installed; then
        error "Docker 未安装。"
        return 1
    fi
    return 0
}

enable_and_start_docker_service() {
    local svc
    svc="$(get_docker_service_name)"

    if cmd_exists systemctl; then
        systemctl enable --now "$svc"
        return $?
    fi

    if cmd_exists service; then
        service "$svc" start
        return $?
    fi

    error "当前系统无法自动管理 Docker 服务。"
    return 1
}

start_docker_service() {
    require_root_action || return 1
    ensure_docker_installed || return 1

    local svc
    svc="$(get_docker_service_name)"

    if cmd_exists systemctl; then
        systemctl start "$svc"
    elif cmd_exists service; then
        service "$svc" start
    else
        error "当前系统无法自动启动 Docker 服务。"
        return 1
    fi

    info "Docker 服务已启动。"
}

stop_docker_service() {
    require_root_action || return 1
    ensure_docker_installed || return 1

    local svc
    svc="$(get_docker_service_name)"

    if cmd_exists systemctl; then
        systemctl stop "$svc"
    elif cmd_exists service; then
        service "$svc" stop
    else
        error "当前系统无法自动停止 Docker 服务。"
        return 1
    fi

    info "Docker 服务已停止。"
}

restart_docker_service() {
    require_root_action || return 1
    ensure_docker_installed || return 1

    local svc
    svc="$(get_docker_service_name)"

    if cmd_exists systemctl; then
        systemctl restart "$svc"
    elif cmd_exists service; then
        service "$svc" restart
    else
        error "当前系统无法自动重启 Docker 服务。"
        return 1
    fi

    info "Docker 服务已重启。"
}

install_or_update_docker() {
    require_root_action || return 1

    print_header "安装/更新 Docker"
    warn "将使用官方 Docker 安装脚本进行安装或更新。"
    warn "安装完成后会自动启用并启动 Docker 服务。"
    echo
    read -r -p "确认继续？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *)
            info "已取消。"
            return 0
            ;;
    esac

    if cmd_exists curl; then
        curl -fsSL https://get.docker.com | sh
    elif cmd_exists wget; then
        wget -qO- https://get.docker.com | sh
    else
        error "缺少 curl/wget，无法下载安装 Docker。"
        return 1
    fi

    enable_and_start_docker_service || return 1

    info "Docker 安装/更新完成。"
    info "$(get_docker_version_text)"
}

install_compose_plugin() {
    require_root_action || return 1

    if docker compose version >/dev/null 2>&1; then
        info "Docker Compose 插件已安装。"
        info "$(docker compose version | head -n1)"
        return 0
    fi

    local pm
    pm="$(get_pkg_manager_docker)"

    case "$pm" in
        apt)
            apt-get update
            apt-get install -y docker-compose-plugin
            ;;
        dnf)
            dnf install -y docker-compose-plugin
            ;;
        yum)
            yum install -y docker-compose-plugin
            ;;
        apk)
            warn "Alpine 通常不使用该方式安装 Docker Compose 插件。"
            warn "你可以直接使用 docker-compose 独立版或自行配置。"
            return 1
            ;;
        *)
            error "未识别包管理器，无法自动安装 Docker Compose 插件。"
            return 1
            ;;
    esac

    if docker compose version >/dev/null 2>&1; then
        info "Docker Compose 插件安装完成。"
        info "$(docker compose version | head -n1)"
        return 0
    fi

    warn "已执行安装，但未检测到 docker compose 命令。"
    warn "可能需要重新登录 shell，或当前仓库源不提供该包。"
    return 1
}

show_containers_interactive() {
    ensure_docker_installed || return 1

    print_header "查看容器"
    cat <<'EOF'
 1. 查看全部容器
 2. 仅查看运行中容器
 3. 查看容器详细信息
 0. 返回
EOF
    echo
    read -r -p "请输入选项: " sub

    case "$sub" in
        1)
            docker ps -a
            ;;
        2)
            docker ps
            ;;
        3)
            local name
            read -r -p "请输入容器名或容器 ID: " name
            [ -z "${name:-}" ] && { warn "不能为空"; return 1; }
            docker inspect "$name"
            ;;
        0)
            return 0
            ;;
        *)
            warn "无效选项"
            ;;
    esac
}

show_images_interactive() {
    ensure_docker_installed || return 1

    print_header "查看镜像"
    cat <<'EOF'
 1. 查看全部镜像
 2. 查看镜像详细信息
 0. 返回
EOF
    echo
    read -r -p "请输入选项: " sub

    case "$sub" in
        1)
            docker images
            ;;
        2)
            local image
            read -r -p "请输入镜像名或镜像 ID: " image
            [ -z "${image:-}" ] && { warn "不能为空"; return 1; }
            docker image inspect "$image"
            ;;
        0)
            return 0
            ;;
        *)
            warn "无效选项"
            ;;
    esac
}

show_networks_interactive() {
    ensure_docker_installed || return 1

    print_header "查看网络"
    cat <<'EOF'
 1. 查看全部网络
 2. 查看网络详细信息
 0. 返回
EOF
    echo
    read -r -p "请输入选项: " sub

    case "$sub" in
        1)
            docker network ls
            ;;
        2)
            local net
            read -r -p "请输入网络名: " net
            [ -z "${net:-}" ] && { warn "不能为空"; return 1; }
            docker network inspect "$net"
            ;;
        0)
            return 0
            ;;
        *)
            warn "无效选项"
            ;;
    esac
}

show_volumes_interactive() {
    ensure_docker_installed || return 1

    print_header "查看卷"
    cat <<'EOF'
 1. 查看全部卷
 2. 查看卷详细信息
 0. 返回
EOF
    echo
    read -r -p "请输入选项: " sub

    case "$sub" in
        1)
            docker volume ls
            ;;
        2)
            local vol
            read -r -p "请输入卷名: " vol
            [ -z "${vol:-}" ] && { warn "不能为空"; return 1; }
            docker volume inspect "$vol"
            ;;
        0)
            return 0
            ;;
        *)
            warn "无效选项"
            ;;
    esac
}

show_container_logs_interactive() {
    ensure_docker_installed || return 1

    local name lines follow
    print_header "容器日志"
    read -r -p "请输入容器名或容器 ID: " name
    [ -z "${name:-}" ] && { warn "不能为空"; return 1; }

    read -r -p "显示最近多少行日志？[默认 100]: " lines
    lines="${lines:-100}"
    [[ "$lines" =~ ^[0-9]+$ ]] || { error "行数格式无效"; return 1; }

    read -r -p "是否持续跟随日志？[y/N]: " follow
    case "$follow" in
        y|Y|yes|YES)
            docker logs --tail "$lines" -f "$name"
            ;;
        *)
            docker logs --tail "$lines" "$name"
            ;;
    esac
}

docker_cleanup_interactive() {
    require_root_action || return 1
    ensure_docker_installed || return 1

    print_header "Docker 清理"
    cat <<'EOF'
 1. 清理停止的容器
 2. 清理悬空镜像
 3. 清理未使用网络
 4. 清理未使用卷
 5. 清理构建缓存
 6. 一键清理全部未使用资源
 0. 返回
EOF
    echo
    read -r -p "请输入选项: " sub

    case "$sub" in
        1)
            docker container prune -f
            ;;
        2)
            docker image prune -f
            ;;
        3)
            docker network prune -f
            ;;
        4)
            docker volume prune -f
            ;;
        5)
            docker builder prune -f
            ;;
        6)
            warn "将清理全部未使用容器/镜像/网络/卷/构建缓存。"
            read -r -p "确认继续？[y/N]: " ans
            case "$ans" in
                y|Y|yes|YES)
                    docker system prune -a -f --volumes
                    ;;
                *)
                    info "已取消。"
                    ;;
            esac
            ;;
        0)
            return 0
            ;;
        *)
            warn "无效选项"
            ;;
    esac
}

create_docker_app_dir() {
    require_root_action || return 1
    mkdir -p "$TBOX_DOCKER_APP_DIR"
    chmod 755 "$TBOX_DOCKER_APP_DIR"
    info "目录已创建: $TBOX_DOCKER_APP_DIR"
}

docker_menu() {
    local choice
    while true; do
        print_header "Docker 工具"
        cat <<EOF
 Docker            : $(get_docker_version_text)
 Compose           : $(get_compose_version_text)
 服务状态          : $(get_docker_service_status_text)
 资源统计          : $(get_docker_counts_summary)

 1. 查看 Docker 状态摘要
 2. 安装/更新 Docker
 3. 安装 Docker Compose 插件
 4. 启动 Docker
 5. 停止 Docker
 6. 重启 Docker
 7. 查看容器
 8. 查看镜像
 9. 查看网络
10. 查看卷
11. 查看容器日志
12. Docker 清理
13. 创建应用目录
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice

        case "$choice" in
            1)
                show_docker_summary
                ;;
            2)
                install_or_update_docker
                ;;
            3)
                install_compose_plugin
                ;;
            4)
                start_docker_service
                ;;
            5)
                stop_docker_service
                ;;
            6)
                restart_docker_service
                ;;
            7)
                show_containers_interactive
                ;;
            8)
                show_images_interactive
                ;;
            9)
                show_networks_interactive
                ;;
            10)
                show_volumes_interactive
                ;;
            11)
                show_container_logs_interactive
                ;;
            12)
                docker_cleanup_interactive
                ;;
            13)
                create_docker_app_dir
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
