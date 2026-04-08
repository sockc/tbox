#!/usr/bin/env bash

TBOX_NAME="tbox"
TBOX_INSTALL_DIR="/usr/local/share/tbox"
TBOX_BIN="/usr/local/bin/tbox"
TBOX_ETC_DIR="/etc/tbox"
TBOX_CONF="${TBOX_ETC_DIR}/tbox.conf"

TBOX_REPO="sockc/tbox"
TBOX_BRANCH="main"

if [ -f "${TBOX_CONF}" ]; then
    # shellcheck source=/dev/null
    . "${TBOX_CONF}"
fi

export TBOX_NAME
export TBOX_INSTALL_DIR
export TBOX_BIN
export TBOX_ETC_DIR
export TBOX_CONF
export TBOX_REPO
export TBOX_BRANCH
