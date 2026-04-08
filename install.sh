#!/usr/bin/env bash
set -Eeuo pipefail

TBOX_REPO="${TBOX_REPO:-sockc/tbox}"
TBOX_BRANCH="${TBOX_BRANCH:-main}"

INSTALL_DIR="/usr/local/share/tbox"
BIN_PATH="/usr/local/bin/tbox"
ETC_DIR="/etc/tbox"
CONF_PATH="${ETC_DIR}/tbox.conf"

log() { printf '%b\n' "$*"; }

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        log "请用 root 运行安装。"
        log "例如：sudo bash install.sh"
        exit 1
    fi
}

fetch_file() {
    local url="$1"
    local out="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --retry 2 "$url" -o "$out"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$out" "$url"
    else
        log "缺少 curl/wget，无法下载安装文件。"
        exit 1
    fi
}

install_from_github() {
    local tmpdir tarball srcdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    tarball="${tmpdir}/tbox.tar.gz"
    fetch_file "https://codeload.github.com/${TBOX_REPO}/tar.gz/refs/heads/${TBOX_BRANCH}" "$tarball"

    tar -xzf "$tarball" -C "$tmpdir"
    srcdir="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n1)"

    if [ -z "${srcdir:-}" ] || [ ! -d "$srcdir" ]; then
        log "下载内容解析失败。"
        exit 1
    fi

    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cp -a "$srcdir"/. "$INSTALL_DIR"/

    find "$INSTALL_DIR" -type f -name "*.sh" -exec chmod +x {} \;
    [ -f "$INSTALL_DIR/bin/tbox" ] && chmod +x "$INSTALL_DIR/bin/tbox"

    mkdir -p "$ETC_DIR"
    cat > "$CONF_PATH" <<EOF
TBOX_REPO='${TBOX_REPO}'
TBOX_BRANCH='${TBOX_BRANCH}'
EOF

    cat > "$BIN_PATH" <<'EOF'
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
    chmod +x "$BIN_PATH"
}

main() {
    require_root
    log "开始安装 tbox ..."
    install_from_github
    log "安装完成。"
    log "命令入口：tbox"
    log "安装目录：${INSTALL_DIR}"
    log "仓库来源：${TBOX_REPO} (${TBOX_BRANCH})"
    log
    exec "$BIN_PATH"
}

main "$@"
