#!/usr/bin/env bash

about_menu() {
    print_header "关于项目"
    cat <<EOF
tbox
一个面向 Linux 服务器的模块化工具箱。

当前目标：
- 先完成统一菜单入口
- 再逐步加入系统、Docker、网络、防火墙、代理、面板、DD 等模块
- 保持模块化，方便后续做脚本集合

当前仓库: ${TBOX_REPO}
当前分支: ${TBOX_BRANCH}
命令入口: ${TBOX_BIN}
安装目录: ${TBOX_INSTALL_DIR}
EOF
    pause
}
