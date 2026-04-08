# tbox

一个用于 Linux VPS / 服务器的模块化工具箱脚本。
一键脚本
````
bash <(curl -fsSL https://raw.githubusercontent.com/sockc/tbox/main/install.sh)
````

## 特点

- 主菜单 + 二级菜单
- 模块化结构，后续方便扩展
- GitHub 托管
- 一键安装
- 一键更新 / 修复 / 卸载
- 安装后命令入口统一为 `tbox`

## 目录结构

```text
tbox/
├── install.sh
├── menu.sh
├── VERSION
├── README.md
├── bin/
│   └── tbox
├── core/
│   ├── common.sh
│   ├── env.sh
│   ├── loader.sh
│   └── updater.sh
└── modules/
    ├── about.sh
    ├── dd.sh
    ├── docker.sh
    ├── firewall.sh
    ├── network.sh
    ├── panel.sh
    ├── proxy.sh
    └── system.sh
