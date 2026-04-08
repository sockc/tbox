#!/usr/bin/env bash

_install_or_update_from_repo() {
    require_root_action || return 1

    local tmpdir tarball srcdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN

    tarball="${tmpdir}/tbox.tar.gz"
    info "正在下载 ${TBOX_REPO} (${TBOX_BRANCH}) ..."
    fetch_url "https://codeload.github.com/${TBOX_REPO}/tar.gz/refs/heads/${TBOX_BRANCH}" "$tarball" || return 1

    tar -xzf "$tarball" -C "$tmpdir"
    srcdir="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n1)"

    if [ -z "${srcdir:-}" ] || [ ! -d "$srcdir" ]; then
        error "下载包解析失败"
        return 1
    fi

    rm -rf "${TBOX_INSTALL_DIR}"
    mkdir -p "${TBOX_INSTALL_DIR}"
    cp -a "$srcdir"/. "${TBOX_INSTALL_DIR}"/

    find "${TBOX_INSTALL_DIR}" -type f -name "*.sh" -exec chmod +x {} \;
    [ -f "${TBOX_INSTALL_DIR}/bin/tbox" ] && chmod +x "${TBOX_INSTALL_DIR}/bin/tbox"

    mkdir -p "${TBOX_ETC_DIR}"
    cat > "${TBOX_CONF}" <<EOF
TBOX_REPO='${TBOX_REPO}'
TBOX_BRANCH='${TBOX_BRANCH}'
EOF

    cat > "${TBOX_BIN}" <<'EOF'
#!/usr/bin/env bash
set -e
if [ -x /usr/local/share/tbox/menu.sh ]; then
    if [ "${EUID:-$(id -u)}" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
        exec sudo -E /usr/local/share/tbox/menu.sh "$@"
    fi
    exec /usr/local/share/tbox/menu.sh "$@"
fi
echo "tbox 未安装或文件缺失。"
exit 1
EOF
    chmod +x "${TBOX_BIN}"

    info "操作完成。"
    return 0
}

update_tbox() {
    info "开始更新 tbox ..."
    _install_or_update_from_repo || return 1
    info "更新完成。"
}

repair_tbox() {
    info "开始修复安装 ..."
    _install_or_update_from_repo || return 1
    info "修复完成。"
}

show_install_info() {
    cat <<EOF
名称       : ${TBOX_NAME}
仓库       : ${TBOX_REPO}
分支       : ${TBOX_BRANCH}
安装目录   : ${TBOX_INSTALL_DIR}
命令入口   : ${TBOX_BIN}
配置文件   : ${TBOX_CONF}
EOF
}

uninstall_tbox() {
    require_root_action || return 1

    warn "即将卸载 tbox"
    read -r -p "确认卸载？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES)
            rm -rf "${TBOX_INSTALL_DIR}" "${TBOX_ETC_DIR}"
            rm -f "${TBOX_BIN}"
            info "tbox 已卸载。"
            exit 0
            ;;
        *)
            info "已取消。"
            ;;
    esac
}
