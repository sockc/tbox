#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="${BASE_DIR}/core"
MODULE_DIR="${BASE_DIR}/modules"
VERSION_FILE="${BASE_DIR}/VERSION"

# shellcheck source=/dev/null
source "${CORE_DIR}/common.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/env.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/loader.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/updater.sh"

SCRIPT_VERSION="dev"
[ -f "${VERSION_FILE}" ] && SCRIPT_VERSION="$(tr -d ' \n\r' < "${VERSION_FILE}")"

show_main_menu() {
    print_header "Linux Toolbox"

    cat <<EOF
 1. 系统工具
 2. Docker 工具
 3. 网络工具
 4. SSH 工具
 5. 防火墙工具
 6. 代理工具
 7. 面板工具
 8. DD/重装工具
 9. 脚本管理
10. 关于项目

 0. 退出

 仓库   : ${TBOX_REPO}
 分支   : ${TBOX_BRANCH}
 版本   : v${SCRIPT_VERSION}
EOF
    echo
}

script_manage_menu() {
    while true; do
        print_header "脚本管理"
        cat <<'EOF'
 1. 更新 tbox
 2. 修复安装
 3. 查看安装信息
 4. 卸载 tbox
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) update_tbox ;;
            2) repair_tbox ;;
            3) show_install_info ;;
            4) uninstall_tbox ;;
            0) return ;;
            *) warn "无效选项" ;;
        esac
        pause
    done
}

main_menu() {
    while true; do
        show_main_menu
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) call_module_menu "system" ;;
            2) call_module_menu "docker" ;;
            3) call_module_menu "network" ;;
            4) call_module_menu "ssh" ;;
            5) call_module_menu "firewall" ;;
            6) call_module_menu "proxy" ;;
            7) call_module_menu "panel" ;;
            8) call_module_menu "dd" ;;
            9) script_manage_menu ;;
            10) call_module_menu "about" ;;
            0) exit 0 ;;
            *) warn "无效选项"; pause ;;
        esac
    done
}

main_menu "$@"
