#!/usr/bin/env bash

call_module_menu() {
    local module_name="$1"
    local module_file="${MODULE_DIR}/${module_name}.sh"
    local func="${module_name}_menu"

    if [ ! -f "${module_file}" ]; then
        error "模块不存在: ${module_name}"
        pause
        return 1
    fi

    # shellcheck source=/dev/null
    source "${module_file}"

    if ! declare -F "${func}" >/dev/null 2>&1; then
        error "模块函数不存在: ${func}"
        pause
        return 1
    fi

    "${func}"
}
