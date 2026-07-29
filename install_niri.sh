#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[install_niri] 错误：命令失败 → $BASH_COMMAND" >&2' ERR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 获取实际用户的 home 目录（sudo 运行时 $HOME 可能指向 /root）
if [[ $EUID -eq 0 && -n "${SUDO_USER-}" && "$SUDO_USER" != "root" ]]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
  USER_HOME="$HOME"
fi

# 一键安装并配置 niri 相关环境
# 该脚本支持交互式菜单，安装 pacman 和 yay 所需软件包，并复制以下配置文件：
#   ~/.config/mako/config
#   ~/.config/xdg-desktop-portal/niri-portals.conf
#   ~/.config/swaylock/config
#   ~/.config/niri/scripts/swayidle.sh
#   ~/.config/satty/config.toml
#   ~/.config/waybar/ (包括 config.jsonc, style.css, power_menu.xml)
#   ~/.local/share/fcitx5/rime/ (fcitx5 rime 配置)
#   ~/.config/niri/config.kdl

PACMAN_PACKAGES=(
  niri
  xdg-desktop-portal-gtk
  xdg-desktop-portal-gnome
  xwayland-satellite
  udiskie
  waybar
  fuzzel
  kitty
  mako
  polkit-gnome
  libnotify
  fcitx5-im
  fcitx5-rime
  rime-ice-pinyin
  rime-wanxiang-pinyin
  thunar
  tumbler
  ffmpegthumbnailer
  poppler-glib
  gvfs-smb
  file-roller
  thunar-archive-plugin
  gnome-keyring
  thunar-volman
  gvfs-mtp
  gvfs-gphoto2
  webp-pixbuf-loader
  icoextract
  python-pillow
  swayidle
  satty
  bazaar
  awww
  ly
)

YAY_PACKAGES=(
  swaylock-effects
  waypaper
  wl-clipboard
  clipse
  clipse-gui
)

log() {
  printf '\n[install_niri] %s\n' "$1"
}

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "错误：未找到命令 '$1'。请先安装它。"
    exit 1
  fi
}

prompt_yes_no() {
  local prompt="${1:-继续吗？}"
  local default="${2:-y}"
  local answer

  while true; do
    if [ -r /dev/tty ]; then
      read -rp "$prompt [Y/n]: " answer </dev/tty
    else
      # non-interactive: use default
      answer="$default"
    fi
    answer="${answer:-$default}"
    case "${answer,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *)
        if [ -r /dev/tty ]; then
          echo "请输入 y 或 n。" > /dev/tty
        else
          echo "请输入 y 或 n。(非交互式环境，使用默认: $default)" >&2
          return 0
        fi
        ;;
    esac
  done
}

run_as_user() {
  local cmd="$*"
  if [[ $EUID -eq 0 ]]; then
    if [[ -z "${SUDO_USER-}" || "$SUDO_USER" == "root" ]]; then
      echo "错误：yay 不能以 root 运行。请以普通用户身份执行此脚本，或使用 sudo 运行但保留 SUDO_USER 环境变量。" >&2
      exit 1
    fi
    local user_home
    user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    sudo -H -u "$SUDO_USER" env HOME="$user_home" bash -lc "$cmd"
  else
    bash -lc "$cmd"
  fi
}

print_menu() {
  cat <<'EOF'
请选择操作:
 1) 安装 pacman 软件包
 2) 安装 yay 软件包
 3) 写入配置文件
 4) 生成/更新 niri 配置
 5) 启用 ly 开机自启 (systemctl enable ly@tty1)
 6) 全部执行
 7) 退出
EOF
}

enable_ly_service() {
  log "启用 ly 系统级开机自启 (ly@tty1)..."
  sudo systemctl enable ly@tty1
}

write_waybar_config() {
  local src="$SCRIPT_DIR/waybar"
  local dst="$USER_HOME/.config/waybar"
  log "复制 waybar 配置: $src → $dst"
  mkdir -p "$dst"
  cp -r "$src"/* "$dst"/
}

write_all_configs() {
  write_mako_config
  write_xdg_portal_config
  write_swaylock_config
  write_swayidle_script
  write_satty_config
  write_rime_custom_yaml
  write_waybar_config
  write_niri_config
}

write_rime_custom_yaml() {
  local src="$SCRIPT_DIR/fcitx5/rime"
  local dst="$USER_HOME/.local/share/fcitx5/rime"
  log "复制 fcitx5 rime 配置: $src → $dst"
  mkdir -p "$dst"
  cp -r "$src"/* "$dst"/
}

install_pacman_packages() {
  ensure_command pacman
  local sudo_cmd=""
  if [[ $EUID -ne 0 ]]; then
    ensure_command sudo
    sudo_cmd=sudo
  fi
  log "更新系统并安装 pacman 软件包..."
  "$sudo_cmd" pacman -Syu --needed --noconfirm "${PACMAN_PACKAGES[@]}"

  # 如果已安装 ly，则尝试启用 systemd 服务 ly@tty1
  if command -v systemctl >/dev/null 2>&1; then
    if pacman -Qs "^ly" >/dev/null 2>&1 || command -v ly >/dev/null 2>&1; then
      log "尝试启用并启动 ly@tty1 服务..."
      if [[ $EUID -ne 0 ]]; then
        ensure_command sudo
        sudo systemctl enable ly@tty1 || log "启用 ly@tty1 服务失败，请手动运行: sudo systemctl enable ly@tty1"
      else
        systemctl enable ly@tty1 || log "启用 ly@tty1 服务失败，请手动运行: sudo systemctl enable ly@tty1"
      fi
    else
      log "ly 未检测到，跳过启用服务步骤。"
    fi
  else
    log "systemctl 未检测到，无法启用 ly 服务。"
  fi
}

ensure_archlinuxcn_repo() {
  local pacman_conf="/etc/pacman.conf"
  if grep -qE '^[[:space:]]*\[archlinuxcn\]' "$pacman_conf" 2>/dev/null; then
    log "archlinuxcn 源已存在，跳过添加。"
    return 0
  fi

  log "archlinuxcn 源未检测到，尝试添加到 $pacman_conf（需要 sudo）..."
  local entry
  entry=$'\n[archlinuxcn]\nSigLevel = Optional TrustedOnly\nServer = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch\n'

  # 在修改 pacman.conf 之前先备份（保存在同一目录，带时间戳）
  local backup_path
  backup_path="${pacman_conf}.backup.$(date +%Y%m%d%H%M%S)"
  if [[ -f "$pacman_conf" ]]; then
    if [[ $EUID -ne 0 ]]; then
      ensure_command sudo
      sudo cp -a "$pacman_conf" "$backup_path"
      sudo chmod --reference="$pacman_conf" "$backup_path" >/dev/null 2>&1 || true
    else
      cp -a "$pacman_conf" "$backup_path"
      chmod --reference="$pacman_conf" "$backup_path" >/dev/null 2>&1 || true
    fi
    log "已备份 $pacman_conf 到 $backup_path"
  else
    log "$pacman_conf 不存在，跳过备份。"
  fi

  if [[ $EUID -ne 0 ]]; then
    ensure_command sudo
    printf '%s' "$entry" | sudo tee -a "$pacman_conf" >/dev/null
  else
    printf '%s' "$entry" >> "$pacman_conf"
  fi

  log "已添加 archlinuxcn 源，刷新软件包数据库..."
  if [[ $EUID -ne 0 ]]; then
    sudo pacman -Sy --noconfirm >/dev/null || true
  else
    pacman -Sy --noconfirm >/dev/null || true
  fi
}

install_yay_packages() {
  # Try to install yay via pacman from archlinuxcn; if repo missing, add it.
  ensure_archlinuxcn_repo

  local sudo_cmd=""
  if [[ $EUID -ne 0 ]]; then
    ensure_command sudo
    sudo_cmd=sudo
  fi

  log "尝试通过 pacman 安装 yay（archlinuxcn）..."
  # install archlinuxcn-keyring first if available to avoid key issues
  "$sudo_cmd" pacman -Sy --needed --noconfirm archlinuxcn-keyring || true
  "$sudo_cmd" pacman -S --needed --noconfirm yay || {
    log "使用 pacman 安装 yay 失败，尝试回退到 AUR 源编译安装..."
    # fallback to building yay from AUR using makepkg (run as normal user)
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tmpdir"
    if [[ $EUID -eq 0 ]]; then
      chown -R "$SUDO_USER":"$SUDO_USER" "$tmpdir"
    fi
    run_as_user "cd '$tmpdir' && makepkg -si --noconfirm"
    rm -rf "$tmpdir"
  }

  log "安装 yay 完成（或已存在）"

  # Install additional YAY_PACKAGES via yay as user
  if command -v yay >/dev/null 2>&1; then
    run_as_user "yay -S --needed --noconfirm ${YAY_PACKAGES[*]}"
  else
    log "yay 未成功安装，跳过 AUR 包安装。"
  fi
}

write_file() {
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" >"$path"
}

append_if_missing() {
  local path="$1"
  local marker="$2"
  local content="$3"
  if ! grep -qF "$marker" "$path" 2>/dev/null; then
    printf '\n%s\n' "$content" >>"$path"
  fi
}

write_mako_config() {
  local src="$SCRIPT_DIR/mako/config"
  local dst="$USER_HOME/.config/mako/config"
  log "复制 mako 配置: $src → $dst"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

write_xdg_portal_config() {
  local src="$SCRIPT_DIR/xdg-desktop-portal/niri-portals.conf"
  local dst="$USER_HOME/.config/xdg-desktop-portal/niri-portals.conf"
  log "复制 xdg-desktop-portal 配置: $src → $dst"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

write_swaylock_config() {
  local src="$SCRIPT_DIR/swaylock/config"
  local dst="$USER_HOME/.config/swaylock/config"
  log "复制 swaylock 配置: $src → $dst"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

write_swayidle_script() {
  local src="$SCRIPT_DIR/niri/scripts/swayidle.sh"
  local dst="$USER_HOME/.config/niri/scripts/swayidle.sh"
  log "复制 swayidle 脚本: $src → $dst"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  chmod +x "$dst"
}

write_satty_config() {
  local src="$SCRIPT_DIR/satty/config.toml"
  local dst="$USER_HOME/.config/satty/config.toml"
  log "复制 satty 配置: $src → $dst"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
}

write_niri_config() {
  local src="$SCRIPT_DIR/niri/config.kdl"
  local dst="$USER_HOME/.config/niri/config.kdl"
  local backup="${dst}.backup.$(date +%Y%m%d%H%M%S)"
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]]; then
    log "备份现有 niri 配置到: $backup"
    cp "$dst" "$backup"
  fi
  log "复制 niri 配置: $src → $dst"
  cp "$src" "$dst"
}

main_menu() {
  while true; do
    print_menu
    if [ -r /dev/tty ]; then
      read -rp "输入选项编号: " choice </dev/tty
    else
      # non-interactive: try to read from stdin, otherwise default to 6 (exit)
      if ! read -r choice; then
        log "检测到非交互式 stdin，自动选择退出。若要无交互安装，请使用 --yes 参数或在终端运行脚本。"
        choice=6
      fi
    fi
    case "$choice" in
      1)
        install_pacman_packages
        ;;
      2)
        install_yay_packages
        ;;
      3)
        write_all_configs
        ;;
      4)
        write_niri_config
        ;;
      5)
        enable_ly_service
        ;;
      6)
        install_pacman_packages
        install_yay_packages
        write_all_configs
        write_niri_config
        enable_ly_service
        ;;
      7)
        log "已退出。"
        exit 0
        ;;
      *)
        echo "无效输入，请输入 1-7 之间的数字。"
        ;;
    esac

    if prompt_yes_no "是否返回主菜单继续操作？" "y"; then
      continue
    fi

    log "安装与配置完成。"
    echo "请根据需要检查 ~/.config/niri/config.kdl 中的配置，并在 niri 启动前确认相关服务能够正确运行。"
    break
  done
}

main_menu "$@"
