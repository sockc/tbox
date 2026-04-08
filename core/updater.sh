#!/usr/bin/env bash

TBOX_BACKUP_DIR="${TBOX_ETC_DIR}/backups/tbox"

get_local_tbox_version() {
    local vf
    vf="${TBOX_INSTALL_DIR}/VERSION"
    [ -f "$vf" ] && tr -d ' \n\r' < "$vf" || echo "unknown"
}

fetch_remote_tbox_version() {
    local url tmp
    url="https://raw.githubusercontent.com/${TBOX_REPO}/${TBOX_BRANCH}/VERSION"
    tmp="$(mktemp)"
    if fetch_url "$url" "$tmp" 2>/dev/null; then
        tr -d ' \n\r' < "$tmp"
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

check_remote_version() {
    local local_ver remote_ver
    local_ver="$(get_local_tbox_version)"
    remote_ver="$(fetch_remote_tbox_version 2>/dev/null || true)"

    echo "本地版本 : ${local_ver}"
    if [ -n "${remote_ver:-}" ]; then
        echo "远程版本 : ${remote_ver}"
        if [ "$local_ver" = "$remote_ver" ]; then
            info "当前已经是最新版本。"
        else
            warn "发现新版本或版本不同。"
        fi
    else
        warn "无法获取远程版本。"
    fi
}

ensure_tbox_backup_dir() {
    mkdir -p "${TBOX_BACKUP_DIR}"
}

backup_current_tbox() {
    require_root_action || return 1
    ensure_tbox_backup_dir

    if [ ! -d "${TBOX_INSTALL_DIR}" ]; then
        error "未找到安装目录：${TBOX_INSTALL_DIR}"
        return 1
    fi

    local ts archive
    ts="$(date '+%Y%m%d_%H%M%S')"
    archive="${TBOX_BACKUP_DIR}/tbox_backup_${ts}.tar.gz"

    if [ -d "${TBOX_ETC_DIR}" ]; then
        tar -czf "$archive" -C / usr/local/share/tbox etc/tbox
    else
        tar -czf "$archive" -C / usr/local/share/tbox
    fi

    info "已备份到：$archive"
}

list_tbox_backups() {
    ensure_tbox_backup_dir
    if ! ls -1 "${TBOX_BACKUP_DIR}"/tbox_backup_*.tar.gz >/dev/null 2>&1; then
        echo "暂无备份。"
        return 0
    fi

    ls -1t "${TBOX_BACKUP_DIR}"/tbox_backup_*.tar.gz
}

rebuild_tbox_bin_wrapper() {
    cat > "${TBOX_BIN}" <<EOF
#!/usr/bin/env bash
set -e
if [ -x "${TBOX_INSTALL_DIR}/menu.sh" ]; then
    if [ "\${EUID:-\$(id -u)}" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
        exec sudo -E "${TBOX_INSTALL_DIR}/menu.sh" "\$@"
    fi
    exec "${TBOX_INSTALL_DIR}/menu.sh" "\$@"
fi
echo "tbox 未安装或文件缺失。"
exit 1
EOF
    chmod +x "${TBOX_BIN}"
}

write_tbox_repo_config() {
    local repo="$1"
    local branch="$2"

    mkdir -p "${TBOX_ETC_DIR}"
    cat > "${TBOX_CONF}" <<EOF
TBOX_REPO='${repo}'
TBOX_BRANCH='${branch}'
EOF
}

validate_repo_format() {
    local repo="$1"
    [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]
}

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
    [ -f "${TBOX_INSTALL_DIR}/menu.sh" ] && chmod +x "${TBOX_INSTALL_DIR}/menu.sh"

    write_tbox_repo_config "${TBOX_REPO}" "${TBOX_BRANCH}"
    rebuild_tbox_bin_wrapper

    info "操作完成。"
    info "当前本地版本：$(get_local_tbox_version)"
    return 0
}

update_tbox() {
    require_root_action || return 1

    print_header "更新 tbox"
    check_remote_version
    echo
    read -r -p "更新前先备份当前安装？[Y/n]: " bak
    case "$bak" in
        n|N|no|NO) ;;
        *) backup_current_tbox || return 1 ;;
    esac

    echo
    read -r -p "确认从 ${TBOX_REPO} (${TBOX_BRANCH}) 更新？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES)
            _install_or_update_from_repo || return 1
            info "更新完成。"
            ;;
        *)
            info "已取消。"
            ;;
    esac
}

repair_tbox() {
    require_root_action || return 1

    print_header "修复安装"
    warn "将重新拉取当前仓库并覆盖安装目录。"
    echo
    read -r -p "修复前先备份当前安装？[Y/n]: " bak
    case "$bak" in
        n|N|no|NO) ;;
        *) backup_current_tbox || return 1 ;;
    esac

    echo
    read -r -p "确认继续修复？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES)
            _install_or_update_from_repo || return 1
            info "修复完成。"
            ;;
        *)
            info "已取消。"
            ;;
    esac
}

switch_tbox_repo_branch_interactive() {
    require_root_action || return 1

    local new_repo new_branch
    print_header "切换仓库/分支"

    echo "当前仓库: ${TBOX_REPO}"
    echo "当前分支: ${TBOX_BRANCH}"
    echo

    read -r -p "请输入新的仓库 [owner/repo]，留空保持不变: " new_repo
    read -r -p "请输入新的分支，留空保持不变: " new_branch

    new_repo="${new_repo:-$TBOX_REPO}"
    new_branch="${new_branch:-$TBOX_BRANCH}"

    if ! validate_repo_format "$new_repo"; then
        error "仓库格式无效，应为 owner/repo"
        return 1
    fi

    if [ -z "${new_branch:-}" ]; then
        error "分支不能为空"
        return 1
    fi

    echo
    echo "新的仓库: ${new_repo}"
    echo "新的分支: ${new_branch}"
    echo
    read -r -p "确认写入并切换？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES)
            write_tbox_repo_config "$new_repo" "$new_branch"
            TBOX_REPO="$new_repo"
            TBOX_BRANCH="$new_branch"
            export TBOX_REPO TBOX_BRANCH
            info "仓库/分支已更新。"
            ;;
        *)
            info "已取消。"
            ;;
    esac
}

restore_tbox_backup_interactive() {
    require_root_action || return 1
    ensure_tbox_backup_dir

    local backups choice selected
    mapfile -t backups < <(ls -1t "${TBOX_BACKUP_DIR}"/tbox_backup_*.tar.gz 2>/dev/null || true)

    if [ "${#backups[@]}" -eq 0 ]; then
        warn "暂无可恢复的备份。"
        return 1
    fi

    print_header "恢复备份"
    echo "可用备份："
    echo

    local i=1
    for selected in "${backups[@]}"; do
        echo " ${i}. $(basename "$selected")"
        i=$((i + 1))
    done
    echo " 0. 取消"
    echo

    read -r -p "请选择要恢复的备份编号: " choice

    if [ "$choice" = "0" ]; then
        info "已取消。"
        return 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        error "输入无效。"
        return 1
    fi

    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
        error "编号超出范围。"
        return 1
    fi

    selected="${backups[$((choice - 1))]}"

    warn "恢复会覆盖当前安装目录和配置目录。"
    read -r -p "恢复前先备份当前安装？[Y/n]: " bak
    case "$bak" in
        n|N|no|NO) ;;
        *) backup_current_tbox || return 1 ;;
    esac

    echo
    read -r -p "确认恢复 $(basename "$selected") ？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES)
            tar -xzf "$selected" -C /
            rebuild_tbox_bin_wrapper
            if [ -f "${TBOX_CONF}" ]; then
                # shellcheck source=/dev/null
                . "${TBOX_CONF}"
                export TBOX_REPO TBOX_BRANCH
            fi
            info "恢复完成。"
            info "当前本地版本：$(get_local_tbox_version)"
            ;;
        *)
            info "已取消。"
            ;;
    esac
}

show_install_info() {
    local remote_ver
    remote_ver="$(fetch_remote_tbox_version 2>/dev/null || true)"

    cat <<EOF
名称         : ${TBOX_NAME}
本地版本     : $(get_local_tbox_version)
远程版本     : ${remote_ver:-未知}
仓库         : ${TBOX_REPO}
分支         : ${TBOX_BRANCH}
安装目录     : ${TBOX_INSTALL_DIR}
命令入口     : ${TBOX_BIN}
配置文件     : ${TBOX_CONF}
备份目录     : ${TBOX_BACKUP_DIR}
EOF
}

uninstall_tbox() {
    require_root_action || return 1

    warn "即将卸载 tbox。"
    read -r -p "卸载前先备份当前安装？[Y/n]: " bak
    case "$bak" in
        n|N|no|NO) ;;
        *) backup_current_tbox || return 1 ;;
    esac

    echo
    read -r -p "确认卸载？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES)
            rm -rf "${TBOX_INSTALL_DIR}"
            rm -f "${TBOX_BIN}"
            info "tbox 主程序已卸载。"
            info "配置和备份目录保留在：${TBOX_ETC_DIR}"
            exit 0
            ;;
        *)
            info "已取消。"
            ;;
    esac
}
