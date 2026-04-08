#!/usr/bin/env bash

SSHD_CONFIG="/etc/ssh/sshd_config"
SSH_CONF_D="/etc/ssh/sshd_config.d"
TBOX_SSH_OVERRIDE="${SSH_CONF_D}/01-tbox.conf"
TBOX_SSH_MARK_BEGIN="# >>> TBOX SSH MANAGED BEGIN >>>"
TBOX_SSH_MARK_END="# <<< TBOX SSH MANAGED END <<<"
TBOX_SSH_BACKUP_DIR="/etc/tbox/backups/ssh"
TBOX_SSH_STATE_DIR="/etc/tbox/state"
TBOX_SSH_PORT_CHANGE_STATE="${TBOX_SSH_STATE_DIR}/ssh_port_change.env"

get_ssh_service_name() {
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then
            echo "sshd"
            return
        fi
        if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
            echo "ssh"
            return
        fi
    fi
    echo "ssh"
}

get_sshd_bin() {
    if command -v sshd >/dev/null 2>&1; then
        command -v sshd
        return
    fi
    [ -x /usr/sbin/sshd ] && { echo "/usr/sbin/sshd"; return; }
    [ -x /usr/local/sbin/sshd ] && { echo "/usr/local/sbin/sshd"; return; }
    echo ""
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

supports_conf_d_override() {
    grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_CONFIG" 2>/dev/null
}

get_effective_value() {
    local key="$1"
    local sshd_bin
    sshd_bin="$(get_sshd_bin)"
    if [ -n "$sshd_bin" ]; then
        "$sshd_bin" -T 2>/dev/null | awk -v k="$key" '$1 == k {print $2; exit}'
    fi
}

get_ssh_port_raw() {
    local v
    v="$(get_effective_value port)"
    if [ -n "${v:-}" ]; then
        echo "$v"
        return
    fi

    if [ -f "$TBOX_SSH_OVERRIDE" ]; then
        v="$(grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' "$TBOX_SSH_OVERRIDE" 2>/dev/null | awk '{print $2}' | head -n1)"
        [ -n "${v:-}" ] && { echo "$v"; return; }
    fi

    v="$(grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' | head -n1)"
    [ -n "${v:-}" ] && echo "$v" || echo "22"
}

get_ssh_port() {
    echo "$(get_ssh_port_raw)"
}

get_root_login_raw() {
    local v
    v="$(get_effective_value permitrootlogin)"
    if [ -n "${v:-}" ]; then
        echo "$v"
        return
    fi

    if [ -f "$TBOX_SSH_OVERRIDE" ]; then
        v="$(grep -E '^[[:space:]]*PermitRootLogin[[:space:]]+' "$TBOX_SSH_OVERRIDE" 2>/dev/null | awk '{print $2}' | head -n1)"
        [ -n "${v:-}" ] && { echo "$v"; return; }
    fi

    v="$(grep -E '^[[:space:]]*PermitRootLogin[[:space:]]+' "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' | head -n1)"
    [ -n "${v:-}" ] && echo "$v" || echo "prohibit-password"
}

get_root_login_status() {
    case "$(get_root_login_raw)" in
        yes) echo "允许" ;;
        no) echo "禁止" ;;
        prohibit-password|without-password) echo "仅密钥" ;;
        forced-commands-only) echo "受限" ;;
        *) echo "默认/未知" ;;
    esac
}

get_password_auth_raw() {
    local v
    v="$(get_effective_value passwordauthentication)"
    if [ -n "${v:-}" ]; then
        echo "$v"
        return
    fi

    if [ -f "$TBOX_SSH_OVERRIDE" ]; then
        v="$(grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+' "$TBOX_SSH_OVERRIDE" 2>/dev/null | awk '{print $2}' | head -n1)"
        [ -n "${v:-}" ] && { echo "$v"; return; }
    fi

    v="$(grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+' "$SSHD_CONFIG" 2>/dev/null | awk '{print $2}' | head -n1)"
    [ -n "${v:-}" ] && echo "$v" || echo "yes"
}

get_password_auth_status() {
    case "$(get_password_auth_raw)" in
        yes) echo "开启" ;;
        no) echo "关闭" ;;
        *) echo "默认/未知" ;;
    esac
}

get_ssh_status() {
    local svc
    svc="$(get_ssh_service_name)"

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo "运行中"
        else
            echo "未运行"
        fi
        return
    fi

    if pgrep -x sshd >/dev/null 2>&1; then
        echo "运行中"
    else
        echo "未知"
    fi
}

ensure_backup_dir() {
    mkdir -p "$TBOX_SSH_BACKUP_DIR"
}

backup_ssh_config() {
    require_root_action || return 1
    ensure_backup_dir

    local ts archive
    ts="$(date '+%Y%m%d_%H%M%S')"
    archive="${TBOX_SSH_BACKUP_DIR}/ssh_backup_${ts}.tar.gz"

    if [ -d "$SSH_CONF_D" ]; then
        tar -czf "$archive" "$SSHD_CONFIG" "$SSH_CONF_D" 2>/dev/null
    else
        tar -czf "$archive" "$SSHD_CONFIG" 2>/dev/null
    fi

    info "已备份 SSH 配置: $archive"
}

ensure_ssh_state_dir() {
    mkdir -p "$TBOX_SSH_STATE_DIR"
}

record_ssh_port_change() {
    local old_port="$1"
    local new_port="$2"

    ensure_ssh_state_dir

    cat > "$TBOX_SSH_PORT_CHANGE_STATE" <<EOF
OLD_PORT='${old_port}'
NEW_PORT='${new_port}'
CHANGED_AT='$(date "+%Y-%m-%d %H:%M:%S")'
EOF
    chmod 600 "$TBOX_SSH_PORT_CHANGE_STATE"
}

clear_ssh_port_change_record() {
    rm -f "$TBOX_SSH_PORT_CHANGE_STATE"
}

load_ssh_port_change_record() {
    [ -f "$TBOX_SSH_PORT_CHANGE_STATE" ] || return 1
    # shellcheck source=/dev/null
    . "$TBOX_SSH_PORT_CHANGE_STATE"
    [ -n "${OLD_PORT:-}" ] && [ -n "${NEW_PORT:-}" ]
}

get_pending_old_ssh_port() {
    if load_ssh_port_change_record; then
        if [ "$(get_ssh_port_raw)" = "${NEW_PORT:-}" ] && [ "${OLD_PORT:-}" != "${NEW_PORT:-}" ]; then
            echo "$OLD_PORT"
            return 0
        fi
    fi
    return 1
}

get_pending_old_ssh_port_text() {
    local oldp
    oldp="$(get_pending_old_ssh_port 2>/dev/null || true)"
    [ -n "${oldp:-}" ] && echo "$oldp" || echo "无"
}

close_old_ssh_port_firewall_rule() {
    local old_port

    require_root_action || return 1

    old_port="$(get_pending_old_ssh_port 2>/dev/null || true)"
    if [ -z "${old_port:-}" ]; then
        warn "没有待关闭的旧 SSH 端口记录。"
        return 1
    fi

    if [ -f "${MODULE_DIR}/firewall.sh" ]; then
        # shellcheck source=/dev/null
        source "${MODULE_DIR}/firewall.sh"
    fi

    if ! declare -F deny_port_backend >/dev/null 2>&1; then
        error "未找到防火墙模块函数 deny_port_backend，请先确认 modules/firewall.sh 已更新。"
        return 1
    fi

    warn "当前 SSH 新端口: $(get_ssh_port_raw)"
    warn "待关闭的旧端口: ${old_port}"
    warn "请先确认你已经可以通过新端口正常登录。"
    read -r -p "确认关闭旧端口 ${old_port}/tcp 的防火墙放行？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES)
            if deny_port_backend "$old_port" "tcp"; then
                info "旧 SSH 端口 ${old_port}/tcp 已关闭放行。"
                clear_ssh_port_change_record
            else
                error "关闭旧 SSH 端口放行失败。"
                return 1
            fi
            ;;
        *)
            info "已取消。"
            ;;
    esac
}

show_ssh_port_change_record() {
    if load_ssh_port_change_record; then
        cat <<EOF
最近一次 SSH 端口变更记录:
旧端口   : ${OLD_PORT}
新端口   : ${NEW_PORT}
变更时间 : ${CHANGED_AT}
EOF
    else
        echo "最近没有记录到 SSH 端口变更。"
    fi
}

strip_managed_block_from_file() {
    local src="$1"
    local dst="$2"
    awk -v begin="$TBOX_SSH_MARK_BEGIN" -v end="$TBOX_SSH_MARK_END" '
        $0 == begin { skip=1; next }
        $0 == end   { skip=0; next }
        !skip { print }
    ' "$src" > "$dst"
}

build_managed_block() {
    local port="$1"
    local root_mode="$2"
    local pass_mode="$3"

    cat <<EOF
$TBOX_SSH_MARK_BEGIN
# Managed by tbox. Do not edit this block manually.
Port $port
PermitRootLogin $root_mode
PasswordAuthentication $pass_mode
$TBOX_SSH_MARK_END
EOF
}

write_managed_ssh_config() {
    local port="$1"
    local root_mode="$2"
    local pass_mode="$3"
    local tmpfile cleanfile

    if supports_conf_d_override; then
        mkdir -p "$SSH_CONF_D"
        tmpfile="$(mktemp)"
        build_managed_block "$port" "$root_mode" "$pass_mode" > "$tmpfile"
        mv "$tmpfile" "$TBOX_SSH_OVERRIDE"
        chmod 600 "$TBOX_SSH_OVERRIDE"
        return 0
    fi

    tmpfile="$(mktemp)"
    cleanfile="$(mktemp)"

    strip_managed_block_from_file "$SSHD_CONFIG" "$cleanfile"

    {
        build_managed_block "$port" "$root_mode" "$pass_mode"
        echo
        cat "$cleanfile"
    } > "$tmpfile"

    cp -f "$tmpfile" "$SSHD_CONFIG"
    chmod 600 "$SSHD_CONFIG"

    rm -f "$tmpfile" "$cleanfile"
}

snapshot_ssh_files() {
    local snapdir="$1"
    mkdir -p "$snapdir"
    cp -a "$SSHD_CONFIG" "$snapdir/sshd_config"

    if [ -f "$TBOX_SSH_OVERRIDE" ]; then
        mkdir -p "$snapdir/sshd_config.d"
        cp -a "$TBOX_SSH_OVERRIDE" "$snapdir/sshd_config.d/01-tbox.conf"
    else
        : > "$snapdir/no_override"
    fi
}

restore_ssh_files() {
    local snapdir="$1"

    [ -f "$snapdir/sshd_config" ] && cp -a "$snapdir/sshd_config" "$SSHD_CONFIG"

    if [ -f "$snapdir/no_override" ]; then
        rm -f "$TBOX_SSH_OVERRIDE"
    elif [ -f "$snapdir/sshd_config.d/01-tbox.conf" ]; then
        mkdir -p "$SSH_CONF_D"
        cp -a "$snapdir/sshd_config.d/01-tbox.conf" "$TBOX_SSH_OVERRIDE"
    fi
}

validate_sshd_config() {
    local sshd_bin
    sshd_bin="$(get_sshd_bin)"

    if [ -z "$sshd_bin" ]; then
        error "未找到 sshd，无法校验 SSH 配置。"
        return 1
    fi

    "$sshd_bin" -t -f "$SSHD_CONFIG"
}

restart_ssh_service() {
    local svc
    svc="$(get_ssh_service_name)"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart "$svc"
        return $?
    fi

    if command -v service >/dev/null 2>&1; then
        service "$svc" restart
        return $?
    fi

    error "当前系统无法自动重启 SSH 服务。"
    return 1
}

allow_port_in_firewall() {
    local port="$1"

    if cmd_exists ufw; then
        ufw allow "${port}/tcp" >/dev/null 2>&1 || ufw allow "${port}/tcp"
        info "已尝试通过 UFW 放行 TCP ${port}"
        return 0
    fi

    if cmd_exists firewall-cmd; then
        firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || firewall-cmd --permanent --add-port="${port}/tcp"
        firewall-cmd --reload >/dev/null 2>&1 || firewall-cmd --reload
        info "已尝试通过 firewalld 放行 TCP ${port}"
        return 0
    fi

    if cmd_exists iptables; then
        iptables -C INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
        if cmd_exists ip6tables; then
            ip6tables -C INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1 || ip6tables -I INPUT -p tcp --dport "$port" -j ACCEPT
        fi
        warn "已尝试通过 iptables 放行 TCP ${port}，但该规则可能不会持久保存。"
        return 0
    fi

    warn "未检测到 UFW / firewalld / iptables，请手动确认防火墙已放行 TCP ${port}"
    return 0
}

apply_managed_ssh_settings() {
    local new_port="$1"
    local new_root="$2"
    local new_pass="$3"
    local old_port snapdir

    require_root_action || return 1

    if ! validate_port "$new_port"; then
        error "端口无效：$new_port"
        return 1
    fi

    old_port="$(get_ssh_port_raw)"
    backup_ssh_config || return 1

    snapdir="$(mktemp -d)"
    snapshot_ssh_files "$snapdir"

    if ! write_managed_ssh_config "$new_port" "$new_root" "$new_pass"; then
        restore_ssh_files "$snapdir"
        rm -rf "$snapdir"
        error "写入 SSH 配置失败"
        return 1
    fi

    if ! validate_sshd_config; then
        restore_ssh_files "$snapdir"
        rm -rf "$snapdir"
        error "SSH 新配置校验失败，已自动回滚。"
        return 1
    fi

    if [ "$new_port" != "$old_port" ]; then
        allow_port_in_firewall "$new_port"
    fi

    if ! restart_ssh_service; then
        restore_ssh_files "$snapdir"
        validate_sshd_config >/dev/null 2>&1 || true
        restart_ssh_service >/dev/null 2>&1 || true
        rm -rf "$snapdir"
        error "SSH 服务重启失败，已回滚到修改前配置。"
        return 1
    fi

    rm -rf "$snapdir"

    if [ "$new_port" != "$old_port" ]; then
        record_ssh_port_change "$old_port" "$new_port"
    fi

    info "SSH 配置已应用。"
    info "当前端口: $(get_ssh_port_raw)"
    info "Root 登录: $(get_root_login_status)"
    info "密码登录: $(get_password_auth_status)"

    if [ "$new_port" != "$old_port" ]; then
        warn "旧端口 ${old_port} 没有自动关闭。"
        warn "请先测试新端口 ${new_port} 可正常连接。"
        warn "确认正常后，再到 SSH 工具里执行“关闭旧 SSH 端口放行”。"
    fi
}

change_ssh_port_interactive() {
    local current_port new_port
    current_port="$(get_ssh_port_raw)"

    print_header "修改 SSH 端口"
    echo "当前 SSH 端口: ${current_port}"
    echo
    read -r -p "请输入新的 SSH 端口: " new_port

    if ! validate_port "$new_port"; then
        error "输入的端口无效。"
        return 1
    fi

    if [ "$new_port" = "$current_port" ]; then
        warn "新端口与当前端口相同，无需修改。"
        return 0
    fi

    echo
    warn "将修改 SSH 端口为: ${new_port}"
    warn "脚本只会自动放行新端口，不会自动关闭旧端口。"
    read -r -p "确认继续？[y/N]: " ans
    case "$ans" in
        y|Y|yes|YES)
            apply_managed_ssh_settings "$new_port" "$(get_root_login_raw)" "$(get_password_auth_raw)"
            ;;
        *)
            info "已取消。"
            ;;
    esac
}

set_root_login_mode_interactive() {
    local current mode
    current="$(get_root_login_raw)"

    while true; do
        print_header "Root 登录管理"
        cat <<EOF
当前 Root 登录状态: $(get_root_login_status)

 1. 允许 Root 登录
 2. 禁止 Root 登录
 3. 仅允许 Root 使用密钥登录
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) mode="yes"; break ;;
            2) mode="no"; break ;;
            3) mode="prohibit-password"; break ;;
            0) return 0 ;;
            *) warn "无效选项"; pause ;;
        esac
    done

    if [ "$mode" = "$current" ]; then
        warn "当前已经是该状态。"
        return 0
    fi

    apply_managed_ssh_settings "$(get_ssh_port_raw)" "$mode" "$(get_password_auth_raw)"
}

set_password_auth_mode_interactive() {
    local current mode
    current="$(get_password_auth_raw)"

    while true; do
        print_header "密码登录管理"
        cat <<EOF
当前密码登录状态: $(get_password_auth_status)

 1. 开启密码登录
 2. 关闭密码登录
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice
        case "$choice" in
            1) mode="yes"; break ;;
            2) mode="no"; break ;;
            0) return 0 ;;
            *) warn "无效选项"; pause ;;
        esac
    done

    if [ "$mode" = "$current" ]; then
        warn "当前已经是该状态。"
        return 0
    fi

    apply_managed_ssh_settings "$(get_ssh_port_raw)" "$(get_root_login_raw)" "$mode"
}

resolve_user_home() {
    local user="$1"
    getent passwd "$user" 2>/dev/null | awk -F: '{print $6}'
}

show_authorized_keys() {
    local user home ak
    read -r -p "查看哪个用户的公钥？[root]: " user
    user="${user:-root}"

    home="$(resolve_user_home "$user")"
    if [ -z "${home:-}" ]; then
        error "用户不存在: $user"
        return 1
    fi

    ak="${home}/.ssh/authorized_keys"
    if [ ! -f "$ak" ]; then
        warn "$user 暂无 authorized_keys"
        return 0
    fi

    echo "文件: $ak"
    echo "----------------------------------------"
    nl -ba "$ak"
    echo "----------------------------------------"
}

add_authorized_key() {
    local user home sshdir ak pubkey
    require_root_action || return 1

    read -r -p "添加到哪个用户？[root]: " user
    user="${user:-root}"

    home="$(resolve_user_home "$user")"
    if [ -z "${home:-}" ]; then
        error "用户不存在: $user"
        return 1
    fi

    read -r -p "请粘贴公钥内容: " pubkey
    if [ -z "${pubkey:-}" ]; then
        warn "公钥内容不能为空。"
        return 1
    fi

    sshdir="${home}/.ssh"
    ak="${sshdir}/authorized_keys"

    mkdir -p "$sshdir"
    chmod 700 "$sshdir"
    touch "$ak"
    chmod 600 "$ak"

    if grep -Fxq "$pubkey" "$ak" 2>/dev/null; then
        warn "该公钥已存在，无需重复添加。"
    else
        echo "$pubkey" >> "$ak"
        info "公钥已添加到 $ak"
    fi

    chown -R "$user":"$user" "$sshdir" 2>/dev/null || true
}

show_ssh_config_summary() {
    echo "主配置文件 : $SSHD_CONFIG"
    echo "覆盖文件   : $TBOX_SSH_OVERRIDE"
    echo "SSH 服务    : $(get_ssh_service_name)"
    echo "服务状态    : $(get_ssh_status)"
    echo "当前端口    : $(get_ssh_port)"
    echo "Root 登录   : $(get_root_login_status)"
    echo "密码登录    : $(get_password_auth_status)"
}

show_ssh_logs() {
    local svc
    svc="$(get_ssh_service_name)"

    if cmd_exists journalctl; then
        journalctl -u "$svc" -n 50 --no-pager || true
        return
    fi

    if [ -f /var/log/auth.log ]; then
        tail -n 50 /var/log/auth.log
        return
    fi

    if [ -f /var/log/secure ]; then
        tail -n 50 /var/log/secure
        return
    fi

    warn "未找到可用 SSH 日志。"
}

show_ssh_config_file() {
    if [ -f "$SSHD_CONFIG" ]; then
        echo "===== $SSHD_CONFIG ====="
        sed -n '1,240p' "$SSHD_CONFIG"
    else
        warn "$SSHD_CONFIG 不存在"
    fi

    if [ -f "$TBOX_SSH_OVERRIDE" ]; then
        echo
        echo "===== $TBOX_SSH_OVERRIDE ====="
        sed -n '1,240p' "$TBOX_SSH_OVERRIDE"
    fi
}

ssh_menu() {
    local choice svc

    while true; do
        print_header "SSH 工具"
        cat <<EOF
 SSH 服务状态     : $(get_ssh_status)
 SSH 端口         : $(get_ssh_port)
 Root 登录        : $(get_root_login_status)
 密码登录         : $(get_password_auth_status)
 待关旧端口       : $(get_pending_old_ssh_port_text)

 1. 查看 SSH 状态摘要
 2. 查看 SSH 配置文件
 3. 备份 SSH 配置
 4. 修改 SSH 端口
 5. Root 登录管理
 6. 密码登录管理
 7. 重启 SSH 服务
 8. 查看 SSH 最近日志
 9. 查看授权公钥
10. 添加授权公钥
11. 查看端口变更记录
12. 关闭旧 SSH 端口放行
 0. 返回上一级
EOF
        echo
        read -r -p "请输入选项: " choice

        case "$choice" in
            1)
                show_ssh_config_summary
                ;;
            2)
                show_ssh_config_file
                ;;
            3)
                backup_ssh_config
                ;;
            4)
                change_ssh_port_interactive
                ;;
            5)
                set_root_login_mode_interactive
                ;;
            6)
                set_password_auth_mode_interactive
                ;;
            7)
                require_root_action || { pause; continue; }
                svc="$(get_ssh_service_name)"
                if restart_ssh_service; then
                    info "SSH 服务已重启: $svc"
                else
                    error "SSH 服务重启失败"
                fi
                ;;
            8)
                show_ssh_logs
                ;;
            9)
                show_authorized_keys
                ;;
            10)
                add_authorized_key
                ;;
            11)
                show_ssh_port_change_record
                ;;
            12)
                close_old_ssh_port_firewall_rule
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
