#!/usr/bin/env bash

DDNSGO_REPO="jeessy2/ddns-go"
DDNSGO_APP_DIR="/usr/local/share/ddns-go"
DDNSGO_BIN="/usr/local/bin/ddns-go"
DDNSGO_ETC_DIR="/etc/ddns-go"
DDNSGO_CONFIG="${DDNSGO_ETC_DIR}/ddns-go.yaml"
DDNSGO_SERVICE_NAME="ddns-go"
DDNSGO_PORT="9876"

LUCKY_REPO="gdy666/lucky"
LUCKY_BIN="/usr/local/bin/lucky"
LUCKY_ETC_DIR="/etc/lucky"
LUCKY_SERVICE_NAME="lucky"
LUCKY_PORT="16601"

custom_http_get() {
    local url="$1"

    if cmd_exists curl; then
        curl -fsSL --connect-timeout 10 --retry 2 "$url" 2>/dev/null
        return $?
    fi

    if cmd_exists wget; then
        wget -qO- "$url" 2>/dev/null
        return $?
    fi

    error "缺少 curl/wget。"
    return 1
}

custom_fetch_to_file() {
    local url="$1"
    local out="$2"

    if cmd_exists curl; then
        curl -fsSL --connect-timeout 10 --retry 2 "$url" -o "$out"
        return $?
    fi

    if cmd_exists wget; then
        wget -qO "$out" "$url"
        return $?
    fi

    error "缺少 curl/wget。"
    return 1
}

project_local_ip() {
    if cmd_exists hostname; then
        hostname -I 2>/dev/null | awk '{print $1}'
        return
    fi

    if cmd_exists ip; then
        ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | head -n1 | cut -d/ -f1
        return
    fi

    echo ""
}

###############################################################################
# DDNS-GO
###############################################################################

ddnsgo_detect_arch() {
    local arch
    arch="$(uname -m 2>/dev/null || echo unknown)"

    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        i386|i486|i586|i686) echo "386" ;;
        aarch64|arm64) echo "arm64" ;;
        armv5*|armv6*|armv7*|arm) echo "arm" ;;
        riscv64) echo "riscv64" ;;
        mips) echo "mips" ;;
        mipsel|mipsle) echo "mipsle" ;;
        mips64) echo "mips64" ;;
        mips64el|mips64le) echo "mips64le" ;;
        *) echo "" ;;
    esac
}

ddnsgo_service_running() {
    if cmd_exists systemctl; then
        systemctl is-active --quiet "${DDNSGO_SERVICE_NAME}" 2>/dev/null
        return $?
    fi

    pgrep -x ddns-go >/dev/null 2>&1
}

ddnsgo_service_status_text() {
    if [ ! -x "${DDNSGO_BIN}" ]; then
        echo "未安装"
        return
    fi

    if ddnsgo_service_running; then
        echo "运行中"
    else
        echo "已安装/未运行"
    fi
}

ddnsgo_print_panel_info() {
    local local_ip public_ip
    local_ip="$(project_local_ip)"
    public_ip="$(get_ipv4)"

    echo
    echo "后台地址："
    echo "  本机访问: http://127.0.0.1:${DDNSGO_PORT}"
    echo "  本机访问: http://localhost:${DDNSGO_PORT}"

    if [ -n "${local_ip:-}" ]; then
        echo "  局域网访问: http://${local_ip}:${DDNSGO_PORT}"
    fi

    if [ -n "${public_ip:-}" ] && [ "${public_ip}" != "N/A" ]; then
        echo "  公网地址: http://${public_ip}:${DDNSGO_PORT}"
    fi

    echo
    warn "如需远程访问，请确认 DDNS-GO 自身允许外部访问，并在防火墙中放行 ${DDNSGO_PORT}/tcp。"
}

ddnsgo_fetch_latest_release_info() {
    local arch="$1"
    local api html

    DDNSGO_LATEST_TAG=""
    DDNSGO_LATEST_URL=""

    api="$(custom_http_get "https://api.github.com/repos/${DDNSGO_REPO}/releases/latest" || true)"
    if [ -n "${api:-}" ]; then
        DDNSGO_LATEST_TAG="$(printf '%s\n' "$api" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
        DDNSGO_LATEST_URL="$(printf '%s\n' "$api" \
            | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            | grep -E "/ddns-go-linux-${arch}[^/]*\.tar\.gz$" \
            | head -n1)"
    fi

    if [ -n "${DDNSGO_LATEST_TAG:-}" ] && [ -n "${DDNSGO_LATEST_URL:-}" ]; then
        return 0
    fi

    html="$(custom_http_get "https://github.com/${DDNSGO_REPO}/releases/latest" || true)"
    if [ -n "${html:-}" ]; then
        DDNSGO_LATEST_TAG="$(printf '%s\n' "$html" | grep -oE "/${DDNSGO_REPO}/releases/tag/[^\"'<> ]+" | head -n1 | awk -F/ '{print $NF}')"
        DDNSGO_LATEST_URL="$(printf '%s\n' "$html" \
            | grep -oE "/${DDNSGO_REPO}/releases/download/[^\"'<> ]*ddns-go-linux-${arch}[^\"'<> ]*\.tar\.gz" \
            | head -n1)"
        [ -n "${DDNSGO_LATEST_URL:-}" ] && DDNSGO_LATEST_URL="https://github.com${DDNSGO_LATEST_URL}"
    fi

    [ -n "${DDNSGO_LATEST_TAG:-}" ] && [ -n "${DDNSGO_LATEST_URL:-}" ]
}

ddnsgo_install_service() {
    "${DDNSGO_BIN}" -s install -l ":${DDNSGO_PORT}" -f 300 -c "${DDNSGO_CONFIG}"
}

ddnsgo_enable_start_service() {
    if cmd_exists systemctl; then
        systemctl daemon-reload >/dev/null 2>&1 || true
        systemctl enable --now "${DDNSGO_SERVICE_NAME}" >/dev/null 2>&1 || systemctl start "${DDNSGO_SERVICE_NAME}"
        return $?
    fi

    if cmd_exists service; then
        service "${DDNSGO_SERVICE_NAME}" start
        return $?
    fi

    return 0
}

ddnsgo_stop_disable_service() {
    if cmd_exists systemctl; then
        systemctl stop "${DDNSGO_SERVICE_NAME}" >/dev/null 2>&1 || true
        systemctl disable "${DDNSGO_SERVICE_NAME}" >/dev/null 2>&1 || true
    elif cmd_exists service; then
        service "${DDNSGO_SERVICE_NAME}" stop >/dev/null 2>&1 || true
    fi
}

ddnsgo_show_status() {
    echo "DDNS-GO 状态 : $(ddnsgo_service_status_text)"
    echo "程序路径     : ${DDNSGO_BIN}"
    echo "配置路径     : ${DDNSGO_CONFIG}"
    echo "监听端口     : ${DDNSGO_PORT}"

    if [ -x "${DDNSGO_BIN}" ]; then
        echo "程序版本     : $("${DDNSGO_BIN}" -v 2>/dev/null || echo 已安装)"
    fi

    ddnsgo_print_panel_info
}

install_ddnsgo_latest() {
    require_root_action || return 1

    local arch tmpdir tarball unpack_dir bin_src

    arch="$(ddnsgo_detect_arch)"
    if [ -z "${arch:-}" ]; then
        error "暂不支持当前架构：$(uname -m 2>/dev/null || echo unknown)"
        return 1
    fi

    info "正在获取 DDNS-GO 最新版本信息..."
    if ! ddnsgo_fetch_latest_release_info "$arch"; then
        error "获取 DDNS-GO 最新版本失败。"
        return 1
    fi

    info "检测到最新版本：${DDNSGO_LATEST_TAG}"
    info "匹配架构包：linux-${arch}"

    tmpdir="$(mktemp -d)"
    tarball="${tmpdir}/ddns-go.tar.gz"
    unpack_dir="${tmpdir}/unpack"
    mkdir -p "$unpack_dir"

    info "正在下载 DDNS-GO ..."
    custom_fetch_to_file "${DDNSGO_LATEST_URL}" "$tarball" || {
        rm -rf "$tmpdir"
        error "下载失败。"
        return 1
    }

    tar -xzf "$tarball" -C "$unpack_dir" || {
        rm -rf "$tmpdir"
        error "解压失败。"
        return 1
    }

    bin_src="$(find "$unpack_dir" -type f -name ddns-go | head -n1)"
    if [ -z "${bin_src:-}" ] || [ ! -f "$bin_src" ]; then
        rm -rf "$tmpdir"
        error "未找到 ddns-go 可执行文件。"
        return 1
    }

    mkdir -p "${DDNSGO_APP_DIR}" "${DDNSGO_ETC_DIR}"
    install -m 755 "$bin_src" "${DDNSGO_BIN}"

    if [ ! -f "${DDNSGO_CONFIG}" ]; then
        touch "${DDNSGO_CONFIG}"
        chmod 600 "${DDNSGO_CONFIG}" >/dev/null 2>&1 || true
    fi

    "${DDNSGO_BIN}" -s uninstall >/dev/null 2>&1 || true

    info "正在安装 DDNS-GO 服务..."
    ddnsgo_install_service || {
        rm -rf "$tmpdir"
        error "服务安装失败。"
        return 1
    }

    ddnsgo_enable_start_service || true
    rm -rf "$tmpdir"

    info "DDNS-GO 安装/更新完成。"
    ddnsgo_print_panel_info
}

uninstall_ddnsgo_interactive() {
    require_root_action || return 1

    warn "即将卸载 DDNS-GO。"
    read -r -p "确认继续？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *)
            info "已取消。"
            return 0
            ;;
    esac

    if [ -x "${DDNSGO_BIN}" ]; then
        "${DDNSGO_BIN}" -s uninstall >/dev/null 2>&1 || true
    fi

    ddnsgo_stop_disable_service
    rm -f "${DDNSGO_BIN}"

    read -r -p "是否同时删除配置目录 ${DDNSGO_ETC_DIR} ？[y/N]: " delcfg
    case "$delcfg" in
        y|Y|yes|YES)
            rm -rf "${DDNSGO_ETC_DIR}"
            info "配置目录已删除。"
            ;;
        *)
            info "已保留配置目录。"
            ;;
    esac

    info "DDNS-GO 已卸载。"
}

custom_ddnsgo_menu() {
    local choice
    while true; do
        print_header "项目脚本 / DDNS-GO"
        cat <<EOF
 DDNS-GO 状态     : $(ddnsgo_service_status_text)
 安装路径         : ${DDNSGO_BIN}
 配置路径         : ${DDNSGO_CONFIG}
 默认端口         : ${DDNSGO_PORT}

 1. 安装/更新 DDNS-GO（自动拉最新版本）
 2. 卸载 DDNS-GO
 3. 查看 DDNS-GO 状态/后台地址
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) install_ddnsgo_latest ;;
            2) uninstall_ddnsgo_interactive ;;
            3) ddnsgo_show_status ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}

###############################################################################
# Lucky
###############################################################################

lucky_detect_arch_pattern() {
    local arch
    arch="$(uname -m 2>/dev/null || echo unknown)"

    case "$arch" in
        x86_64|amd64) echo "amd64|x86_64" ;;
        i386|i486|i586|i686) echo "386|i386|x86" ;;
        aarch64|arm64) echo "arm64|aarch64" ;;
        armv5*|armv6*|armv7*|arm) echo "armv7|armv6|armv5|arm" ;;
        mipsel|mipsle) echo "mipsle|mipsel" ;;
        mips64el|mips64le) echo "mips64le|mips64el" ;;
        mips64) echo "mips64" ;;
        mips) echo "mips" ;;
        riscv64) echo "riscv64" ;;
        *) echo "" ;;
    esac
}

lucky_service_running() {
    if cmd_exists systemctl; then
        systemctl is-active --quiet "${LUCKY_SERVICE_NAME}" 2>/dev/null
        return $?
    fi

    pgrep -x lucky >/dev/null 2>&1
}

lucky_service_status_text() {
    if [ ! -x "${LUCKY_BIN}" ]; then
        echo "未安装"
        return
    fi

    if lucky_service_running; then
        echo "运行中"
    else
        echo "已安装/未运行"
    fi
}

lucky_print_panel_info() {
    local local_ip public_ip
    local_ip="$(project_local_ip)"
    public_ip="$(get_ipv4)"

    echo
    echo "后台地址："
    if [ -n "${local_ip:-}" ]; then
        echo "  局域网访问: http://${local_ip}:${LUCKY_PORT}"
    fi

    if [ -n "${public_ip:-}" ] && [ "${public_ip}" != "N/A" ]; then
        echo "  公网地址: http://${public_ip}:${LUCKY_PORT}"
    fi

    echo
    echo "默认账号: 666"
    echo "默认密码: 666"
    echo
    warn "如需远程访问，请确认防火墙已放行 ${LUCKY_PORT}/tcp。"
}

lucky_fetch_latest_release_info() {
    local arch_pattern="$1"
    local api html

    LUCKY_LATEST_TAG=""
    LUCKY_LATEST_URL=""

    api="$(custom_http_get "https://api.github.com/repos/${LUCKY_REPO}/releases/latest" || true)"
    if [ -n "${api:-}" ]; then
        LUCKY_LATEST_TAG="$(printf '%s\n' "$api" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
        LUCKY_LATEST_URL="$(printf '%s\n' "$api" \
            | sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            | grep -Ei "linux.*(${arch_pattern}).*\.tar\.gz$|(${arch_pattern}).*linux.*\.tar\.gz$" \
            | head -n1)"
    fi

    if [ -n "${LUCKY_LATEST_TAG:-}" ] && [ -n "${LUCKY_LATEST_URL:-}" ]; then
        return 0
    fi

    html="$(custom_http_get "https://github.com/${LUCKY_REPO}/releases/latest" || true)"
    if [ -n "${html:-}" ]; then
        LUCKY_LATEST_TAG="$(printf '%s\n' "$html" | grep -oE "/${LUCKY_REPO}/releases/tag/[^\"'<> ]+" | head -n1 | awk -F/ '{print $NF}')"
        LUCKY_LATEST_URL="$(printf '%s\n' "$html" \
            | grep -oE "/${LUCKY_REPO}/releases/download/[^\"'<> ]+\.tar\.gz" \
            | grep -Ei "linux.*(${arch_pattern})|(${arch_pattern}).*linux" \
            | head -n1)"
        [ -n "${LUCKY_LATEST_URL:-}" ] && LUCKY_LATEST_URL="https://github.com${LUCKY_LATEST_URL}"
    fi

    [ -n "${LUCKY_LATEST_TAG:-}" ] && [ -n "${LUCKY_LATEST_URL:-}" ]
}

lucky_write_service_unit() {
    cat > /etc/systemd/system/${LUCKY_SERVICE_NAME}.service <<EOF
[Unit]
Description=Lucky Service
After=network.target

[Service]
Type=simple
ExecStart=${LUCKY_BIN} -cd ${LUCKY_ETC_DIR}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
}

lucky_enable_start_service() {
    if cmd_exists systemctl; then
        systemctl daemon-reload
        systemctl enable --now "${LUCKY_SERVICE_NAME}"
        return $?
    fi

    error "当前系统缺少 systemctl，Lucky 这版安装脚本仅实现了 systemd 服务方式。"
    return 1
}

lucky_stop_disable_service() {
    if cmd_exists systemctl; then
        systemctl stop "${LUCKY_SERVICE_NAME}" >/dev/null 2>&1 || true
        systemctl disable "${LUCKY_SERVICE_NAME}" >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/${LUCKY_SERVICE_NAME}.service
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi
}

lucky_show_status() {
    echo "Lucky 状态     : $(lucky_service_status_text)"
    echo "程序路径       : ${LUCKY_BIN}"
    echo "配置目录       : ${LUCKY_ETC_DIR}"
    echo "默认端口       : ${LUCKY_PORT}"

    if [ -x "${LUCKY_BIN}" ]; then
        echo "程序版本       : $("${LUCKY_BIN}" -v 2>/dev/null | head -n1 || echo 已安装)"
    fi

    lucky_print_panel_info
}

install_lucky_latest() {
    require_root_action || return 1

    local arch_pattern tmpdir tarball unpack_dir bin_src

    arch_pattern="$(lucky_detect_arch_pattern)"
    if [ -z "${arch_pattern:-}" ]; then
        error "暂不支持当前架构：$(uname -m 2>/dev/null || echo unknown)"
        return 1
    fi

    info "正在获取 Lucky 最新版本信息..."
    if ! lucky_fetch_latest_release_info "$arch_pattern"; then
        error "获取 Lucky 最新版本失败。"
        return 1
    fi

    info "检测到最新版本：${LUCKY_LATEST_TAG}"

    tmpdir="$(mktemp -d)"
    tarball="${tmpdir}/lucky.tar.gz"
    unpack_dir="${tmpdir}/unpack"
    mkdir -p "$unpack_dir"

    info "正在下载 Lucky ..."
    custom_fetch_to_file "${LUCKY_LATEST_URL}" "$tarball" || {
        rm -rf "$tmpdir"
        error "下载失败。"
        return 1
    }

    tar -xzf "$tarball" -C "$unpack_dir" || {
        rm -rf "$tmpdir"
        error "解压失败。"
        return 1
    }

    bin_src="$(find "$unpack_dir" -type f -name lucky | head -n1)"
    if [ -z "${bin_src:-}" ] || [ ! -f "$bin_src" ]; then
        rm -rf "$tmpdir"
        error "未找到 lucky 可执行文件。"
        return 1
    fi

    mkdir -p "${LUCKY_ETC_DIR}"
    install -m 755 "$bin_src" "${LUCKY_BIN}"

    lucky_stop_disable_service
    lucky_write_service_unit
    lucky_enable_start_service || {
        rm -rf "$tmpdir"
        error "Lucky 服务启动失败。"
        return 1
    }

    rm -rf "$tmpdir"

    info "Lucky 安装/更新完成。"
    lucky_print_panel_info
}

uninstall_lucky_interactive() {
    require_root_action || return 1

    warn "即将卸载 Lucky。"
    read -r -p "确认继续？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *)
            info "已取消。"
            return 0
            ;;
    esac

    lucky_stop_disable_service
    rm -f "${LUCKY_BIN}"

    read -r -p "是否同时删除配置目录 ${LUCKY_ETC_DIR} ？[y/N]: " delcfg
    case "$delcfg" in
        y|Y|yes|YES)
            rm -rf "${LUCKY_ETC_DIR}"
            info "配置目录已删除。"
            ;;
        *)
            info "已保留配置目录。"
            ;;
    esac

    info "Lucky 已卸载。"
}

custom_lucky_menu() {
    local choice
    while true; do
        print_header "项目脚本 / Lucky"
        cat <<EOF
 Lucky 状态       : $(lucky_service_status_text)
 安装路径         : ${LUCKY_BIN}
 配置目录         : ${LUCKY_ETC_DIR}
 默认端口         : ${LUCKY_PORT}

 1. 安装/更新 Lucky（自动拉最新版本）
 2. 卸载 Lucky
 3. 查看 Lucky 状态/后台地址
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) install_lucky_latest ;;
            2) uninstall_lucky_interactive ;;
            3) lucky_show_status ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}

###############################################################################
# DD / 其它菜单
###############################################################################

custom_dd_menu() {
    local choice
    while true; do
        print_header "项目脚本 / DD"
        cat <<'EOF'
 1. DD 重装脚本（占位）
 2. 网络信息预检脚本（占位）
 3. 引导修复脚本（占位）
 4. DD 后检查脚本（占位）
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) info "后续这里放你的 DD 重装脚本。" ;;
            2) info "后续这里放 DD 前网络信息预检脚本。" ;;
            3) info "后续这里放引导修复脚本。" ;;
            4) info "后续这里放 DD 后检查脚本。" ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}

custom_projects_menu() {
    local choice
    while true; do
        print_header "自建脚本集合 / 项目脚本"
        cat <<'EOF'
 1. DD
 2. DDNS-GO
 3. Lucky
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) custom_dd_menu ;;
            2) custom_ddnsgo_menu ;;
            3) custom_lucky_menu ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}

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
 1. 项目脚本
 2. 服务器脚本
 3. 维护脚本
 4. 其它脚本
 5. 查看规划说明
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice

        case "$choice" in
            1) custom_projects_menu ;;
            2) custom_server_menu ;;
            3) custom_maint_menu ;;
            4) custom_other_menu ;;
            5)
                cat <<'EOT'
当前结构：

自建脚本集合
├── 项目脚本
│   ├── DD
│   ├── DDNS-GO
│   └── Lucky
├── 服务器脚本
├── 维护脚本
└── 其它脚本

这样后面继续加自己的项目，会比直接平铺在第一层更整齐。
EOT
                ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac

        pause
    done
}
