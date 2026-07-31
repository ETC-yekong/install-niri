# install_niri

一键安装并配置 Niri（Wayland 合成器）相关环境的自动化脚本。

## 功能

- 通过 pacman 和 yay 自动安装所需软件包
- 自动配置 archlinuxcn 源
- 将预配置好的配置文件复制到对应路径
- 启用 ly 显示管理器开机自启

## 包含的配置

| 软件 | 配置路径 |
|------|----------|
| niri | `~/.config/niri/config.kdl` |
| swayidle | `~/.config/niri/scripts/swayidle.sh` |
| waybar | `~/.config/waybar/` |
| mako | `~/.config/mako/config` |
| swaylock | `~/.config/swaylock/config` |
| satty | `~/.config/satty/config.toml` |
| fcitx5-rime | `~/.local/share/fcitx5/rime/` |
| xdg-desktop-portal | `~/.config/xdg-desktop-portal/niri-portals.conf` |

## 前置要求

- Arch Linux 或基于 Arch 的发行版
- 网络连接
- `sudo` 权限

## 使用方法

```bash
# 克隆仓库
git clone https://github.com/<你的用户名>/install_niri.git
cd install_niri

# 添加执行权限
chmod +x install_niri.sh

# 以普通用户身份运行（不要 sudo）
./install_niri.sh

# 非交互执行（自动选择“全部执行”）
./install_niri.sh --yes

# 非交互执行指定菜单项（例如 3: 写入配置）
./install_niri.sh --action 3
```

## 菜单说明

```
请选择操作:
 1) 安装 pacman 软件包
 2) 安装 yay 软件包
 3) 写入配置文件
 4) 生成/更新 niri 配置
 5) 启用 ly 开机自启 (systemctl enable ly@tty1)
 6) 全部执行
 7) 退出
```

| 选项 | 说明 |
|------|------|
| 1 | 安装 niri、waybar、mako、fcitx5 等 pacman 官方源和 archlinuxcn 源的软件包 |
| 2 | 安装 swaylock-effects、waypaper、wl-clipboard 等 AUR 软件包（会自动安装 yay） |
| 3 | 将仓库中的配置文件复制到 `~/.config/` 和 `~/.local/share/` |
| 4 | 单独更新 niri 配置文件（已有配置会自动备份） |
| 5 | 启用 ly 显示管理器的 systemd 服务 |
| 6 | 按顺序执行 1→2→3→4→5，推荐首次使用时选择 |
| 7 | 退出脚本 |

## 注意事项

- **请以普通用户身份运行**，脚本内部会自动调用 sudo 安装软件包
- 选择 `6) 全部执行` 会先安装软件包，再写入配置文件
- niri 配置文件在覆盖前会自动备份，备份文件名带时间戳
- 安装完成后需注销或重启，选择 niri 作为会话登录即可

## 自定义配置

如需修改配置，直接编辑仓库中对应子目录下的文件即可，再次运行脚本的选项 `3` 或 `6` 会重新复制。

## 目录结构

```
install_niri/
├── install_niri.sh          # 主脚本
├── fcitx5/rime/             # fcitx5 rime 输入法配置
├── mako/config              # mako 通知配置
├── niri/
│   ├── config.kdl           # niri 合成器配置
│   └── scripts/swayidle.sh  # swayidle 锁屏/休眠脚本
├── satty/config.toml        # satty 截图工具配置
├── swaylock/config          # swaylock 锁屏配置
├── waybar/                  # waybar 状态栏配置
│   ├── config.jsonc
│   ├── style.css
│   └── power_menu.xml
└── xdg-desktop-portal/      # xdg-desktop-portal 配置
    └── niri-portals.conf
```
