#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

handle_error() {
  local msg
  if [[ "${UI_LANG:-en}" == "zh" ]]; then
    msg="错误：命令失败 → ${BASH_COMMAND}"
  else
    msg="Error: command failed → ${BASH_COMMAND}"
  fi
  echo "[install_niri] $msg" >&2
}

trap 'handle_error' ERR

# 获取实际用户的 home 目录（sudo 运行时 $HOME 可能指向 /root）
if [[ $EUID -eq 0 && -n "${SUDO_USER-}" && "$SUDO_USER" != "root" ]]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
  USER_HOME="$HOME"
fi

detect_ui_lang() {
  local locale="${LANG:-${LC_ALL:-${LC_MESSAGES:-C}}}"
  locale="${locale%%.*}"
  locale="${locale%%@*}"
  locale="${locale,,}"
  case "$locale" in
    zh*|cn*|tw*|hk*) echo "zh" ;;
    *) echo "en" ;;
  esac
}

tr() {
  local key="$1"
  local zh="$2"
  local en="$3"
  if [[ "${UI_LANG:-$(detect_ui_lang)}" == "zh" ]]; then
    printf '%s' "$zh"
  else
    printf '%s' "$en"
  fi
}

UI_LANG="$(detect_ui_lang)"

AUTO_YES=false
AUTO_ACTION=""

parse_args() {
  while (($#)); do
    case "$1" in
      --yes)
        AUTO_YES=true
        ;;
      --action)
        shift
        if [[ $# -eq 0 ]]; then
          echo "$(tr "action_requires_value" "错误：--action 需要一个参数（1-7）。" "Error: --action requires a value (1-7).")" >&2
          exit 1
        fi
        AUTO_ACTION="$1"
        AUTO_YES=true
        ;;
      -h|--help)
        if [[ "$UI_LANG" == "zh" ]]; then
          cat <<'EOF'
用法: ./install_niri.sh [--yes] [--action 1|2|3|4|5|6|7]
  --yes            非交互模式，自动选择默认操作（默认执行 6: 全部执行）
  --action N       非交互模式下直接执行指定菜单项
  -h, --help       显示帮助信息
EOF
        else
          cat <<'EOF'
Usage: ./install_niri.sh [--yes] [--action 1|2|3|4|5|6|7]
  --yes            Non-interactive mode; run the default action (6: run everything)
  --action N       Run the specified menu item in non-interactive mode
  -h, --help       Show help information
EOF
        fi
        exit 0
        ;;
      *)
        echo "$(tr "unknown_arg" "错误：未知参数 '$1'。使用 --help 查看帮助。" "Error: unknown argument '$1'. Use --help to see usage.")" >&2
        exit 1
        ;;
    esac
    shift
  done
}

parse_args "$@"

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
  ttf-jetbrains-mono-nerd
  otf-font-awesome
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

show_stage() {
  local stage="$1"
  local summary="$2"
  if [[ "${UI_LANG:-$(detect_ui_lang)}" == "zh" ]]; then
    printf '\n[install_niri] ===== %s =====\n' "$stage"
    printf '[install_niri] %s\n' "$summary"
  else
    printf '\n[install_niri] ===== %s =====\n' "$stage"
    printf '[install_niri] %s\n' "$summary"
  fi
}

ensure_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$(tr "ensure_command" "错误：未找到命令 '$1'。请先安装它。" "Error: command '$1' was not found. Please install it first.")"
    exit 1
  fi
}

ensure_writable_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    if [[ -w "$dir" ]]; then
      return 0
    fi
  fi

  if mkdir -p "$dir" 2>/dev/null && [[ -w "$dir" ]]; then
    return 0
  fi

  if [[ $EUID -ne 0 ]] && command -v sudo >/dev/null 2>&1; then
    local user_name
    user_name=$(id -un)
    local group_name
    group_name=$(id -gn)
    if sudo mkdir -p "$dir" && sudo chown -R "$user_name:$group_name" "$dir"; then
      return 0
    fi
  fi

  echo "错误：无法创建或写入目录 '$dir'。" >&2
  return 1
}

prompt_yes_no() {
  local prompt="${1:-$(tr "prompt_default" "继续吗？" "Continue?")}" 
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
          echo "$(tr "prompt_invalid" "请输入 y 或 n。" "Please enter y or n.")" > /dev/tty
        else
          echo "$(tr "prompt_invalid_noninteractive" "请输入 y 或 n。(非交互式环境，使用默认: $default)" "Please enter y or n. (non-interactive mode, using default: $default)")" >&2
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
      echo "$(tr "run_as_user_root" "错误：yay 不能以 root 运行。请以普通用户身份执行此脚本，或使用 sudo 运行但保留 SUDO_USER 环境变量。" "Error: yay cannot run as root. Please run this script as a normal user, or run it with sudo while preserving the SUDO_USER environment variable.")" >&2
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
  printf '%s\n' "$(tr "menu_title" "请选择操作:" "Please choose an operation:")"
  printf ' 1) %s\n' "$(tr "menu_pacman" "安装 pacman 软件包" "Install pacman packages")"
  printf ' 2) %s\n' "$(tr "menu_yay" "安装 yay 软件包" "Install yay packages")"
  printf ' 3) %s\n' "$(tr "menu_configs" "写入配置文件" "Write configuration files")"
  printf ' 4) %s\n' "$(tr "menu_niri" "生成/更新 niri 配置" "Generate/update niri configuration")"
  printf ' 5) %s\n' "$(tr "menu_ly" "启用 ly 开机自启 (systemctl enable ly@tty1)" "Enable ly at boot (systemctl enable ly@tty1)")"
  printf ' 6) %s\n' "$(tr "menu_all" "全部执行" "Run everything")"
  printf ' 7) %s\n' "$(tr "menu_exit" "退出" "Exit")"
}

enable_ly_service() {
  show_stage "Stage 5: Enable display manager" "Enabling the ly display manager service at boot"
  log "$(tr "enable_ly" "启用 ly 系统级开机自启 (ly@tty1)..." "Enabling ly system service (ly@tty1)...")"
  if [[ $EUID -ne 0 ]]; then
    ensure_command sudo
    sudo systemctl enable ly@tty1
  else
    systemctl enable ly@tty1
  fi
}

write_waybar_config() {
  local src="$SCRIPT_DIR/waybar"
  local dst="$USER_HOME/.config/waybar"
  log "$(tr "copy_waybar" "复制 waybar 配置: $src → $dst" "Copying waybar config: $src → $dst")"
  ensure_writable_dir "$dst"
  cp -r "$src"/* "$dst"/
}

write_all_configs() {
  show_stage "Stage 3: Write config files" "Copying all repository configuration files into place"
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
  log "$(tr "copy_rime" "复制 fcitx5 rime 配置: $src → $dst" "Copying fcitx5 rime config: $src → $dst")"
  ensure_writable_dir "$dst"
  cp -r "$src"/* "$dst"/
}

install_pacman_packages() {
  show_stage "Stage 1: Install pacman packages" "Preparing to update the system and install pacman packages"
  ensure_command pacman
  local sudo_cmd=()
  if [[ $EUID -ne 0 ]]; then
    ensure_command sudo
    sudo_cmd=(sudo)
  fi
  log "$(tr "pacman_install" "更新系统并安装 pacman 软件包..." "Updating the system and installing pacman packages...")"
  "${sudo_cmd[@]}" pacman -Syu --needed --noconfirm "${PACMAN_PACKAGES[@]}"

  # 如果已安装 ly，则尝试启用 systemd 服务 ly@tty1
  if command -v systemctl >/dev/null 2>&1; then
    if pacman -Qs "^ly" >/dev/null 2>&1 || command -v ly >/dev/null 2>&1; then
      log "$(tr "ly_try_enable" "尝试启用并启动 ly@tty1 服务..." "Trying to enable and start the ly@tty1 service...")"
      if [[ $EUID -ne 0 ]]; then
        ensure_command sudo
        sudo systemctl enable ly@tty1 || log "$(tr "ly_enable_failed" "启用 ly@tty1 服务失败，请手动运行: sudo systemctl enable ly@tty1" "Failed to enable the ly@tty1 service. Please run: sudo systemctl enable ly@tty1")"
      else
        systemctl enable ly@tty1 || log "$(tr "ly_enable_failed" "启用 ly@tty1 服务失败，请手动运行: sudo systemctl enable ly@tty1" "Failed to enable the ly@tty1 service. Please run: sudo systemctl enable ly@tty1")"
      fi
    else
      log "$(tr "ly_not_found" "ly 未检测到，跳过启用服务步骤。" "ly was not detected; skipping service enablement.")"
    fi
  else
    log "$(tr "systemctl_not_found" "systemctl 未检测到，无法启用 ly 服务。" "systemctl was not detected; cannot enable the ly service.")"
  fi
}

ensure_archlinuxcn_repo() {
  local pacman_conf="/etc/pacman.conf"
  if grep -qE '^[[:space:]]*\[archlinuxcn\]' "$pacman_conf" 2>/dev/null; then
    log "$(tr "repo_exists" "archlinuxcn 源已存在，跳过添加。" "The archlinuxcn repository already exists; skipping add.")"
    return 0
  fi

  log "$(tr "repo_add" "archlinuxcn 源未检测到，尝试添加到 $pacman_conf（需要 sudo）..." "The archlinuxcn repository was not detected; trying to add it to $pacman_conf (requires sudo)...")"
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
    log "$(tr "repo_backup" "已备份 $pacman_conf 到 $backup_path" "Backed up $pacman_conf to $backup_path")"
  else
    log "$(tr "pacman_conf_missing" "$pacman_conf 不存在，跳过备份。" "$pacman_conf does not exist; skipping backup.")"
  fi

  if [[ $EUID -ne 0 ]]; then
    ensure_command sudo
    printf '%s' "$entry" | sudo tee -a "$pacman_conf" >/dev/null
  else
    printf '%s' "$entry" >> "$pacman_conf"
  fi

  log "$(tr "repo_added" "已添加 archlinuxcn 源，刷新软件包数据库..." "Added the archlinuxcn repository; refreshing the package database...")"
  if [[ $EUID -ne 0 ]]; then
    sudo pacman -Sy --noconfirm >/dev/null || true
  else
    pacman -Sy --noconfirm >/dev/null || true
  fi
}

install_yay_packages() {
  show_stage "Stage 2: Install yay and AUR packages" "Preparing to install yay and additional AUR packages"
  # Try to install yay via pacman from archlinuxcn; if repo missing, add it.
  ensure_archlinuxcn_repo

  local sudo_cmd=()
  if [[ $EUID -ne 0 ]]; then
    ensure_command sudo
    sudo_cmd=(sudo)
  fi

  log "$(tr "yay_install" "尝试通过 pacman 安装 yay（archlinuxcn）..." "Trying to install yay via pacman (archlinuxcn)...")"
  # install archlinuxcn-keyring first if available to avoid key issues
  "${sudo_cmd[@]}" pacman -Sy --needed --noconfirm archlinuxcn-keyring || true
  "${sudo_cmd[@]}" pacman -S --needed --noconfirm yay || {
    log "$(tr "yay_fallback" "使用 pacman 安装 yay 失败，尝试回退到 AUR 源编译安装..." "Installing yay via pacman failed; trying the AUR build fallback...")"
    ensure_command git
    # fallback to building yay from AUR using makepkg (run as normal user)
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tmpdir"
    if [[ $EUID -eq 0 ]]; then
      chown -R "$SUDO_USER":"$SUDO_USER" "$tmpdir"
    fi
    run_as_user "cd '$tmpdir' && makepkg -si --noconfirm"
    rm -rf "$tmpdir"
  }

  log "$(tr "yay_done" "安装 yay 完成（或已存在）" "yay installation is complete (or already present)")"

  # Install additional YAY_PACKAGES via yay as user
  if command -v yay >/dev/null 2>&1; then
    run_as_user "yay -S --needed --noconfirm ${YAY_PACKAGES[*]}"
  else
    log "$(tr "yay_skip" "yay 未成功安装，跳过 AUR 包安装。" "yay was not installed successfully; skipping AUR package installation.")"
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
  log "$(tr "copy_mako" "复制 mako 配置: $src → $dst" "Copying mako config: $src → $dst")"
  ensure_writable_dir "$(dirname "$dst")"
  cp "$src" "$dst"
}

write_xdg_portal_config() {
  local src="$SCRIPT_DIR/xdg-desktop-portal/niri-portals.conf"
  local dst="$USER_HOME/.config/xdg-desktop-portal/niri-portals.conf"
  log "$(tr "copy_xdg" "复制 xdg-desktop-portal 配置: $src → $dst" "Copying xdg-desktop-portal config: $src → $dst")"
  ensure_writable_dir "$(dirname "$dst")"
  cp "$src" "$dst"
}

write_swaylock_config() {
  local src="$SCRIPT_DIR/swaylock/config"
  local dst="$USER_HOME/.config/swaylock/config"
  log "$(tr "copy_swaylock" "复制 swaylock 配置: $src → $dst" "Copying swaylock config: $src → $dst")"
  ensure_writable_dir "$(dirname "$dst")"
  cp "$src" "$dst"
}

write_swayidle_script() {
  local src="$SCRIPT_DIR/niri/scripts/swayidle.sh"
  local dst="$USER_HOME/.config/niri/scripts/swayidle.sh"
  log "$(tr "copy_swayidle" "复制 swayidle 脚本: $src → $dst" "Copying swayidle script: $src → $dst")"
  ensure_writable_dir "$(dirname "$dst")"
  cp "$src" "$dst"
  chmod +x "$dst"
}

write_satty_config() {
  local src="$SCRIPT_DIR/satty/config.toml"
  local dst="$USER_HOME/.config/satty/config.toml"
  log "$(tr "copy_satty" "复制 satty 配置: $src → $dst" "Copying satty config: $src → $dst")"
  ensure_writable_dir "$(dirname "$dst")"
  cp "$src" "$dst"
}

write_niri_config() {
  show_stage "Stage 4: Update niri config" "Updating the niri configuration file and creating a backup if needed"
  local src="$SCRIPT_DIR/niri/config.kdl"
  local dst="$USER_HOME/.config/niri/config.kdl"
  local backup="${dst}.backup.$(date +%Y%m%d%H%M%S)"
  ensure_writable_dir "$(dirname "$dst")"
  if [[ -f "$dst" ]]; then
    log "$(tr "backup_niri" "备份现有 niri 配置到: $backup" "Backed up the existing niri config to: $backup")"
    cp "$dst" "$backup"
  fi
  log "$(tr "copy_niri" "复制 niri 配置: $src → $dst" "Copying niri config: $src → $dst")"
  cp "$src" "$dst"
}

main_menu() {
  while true; do
    show_stage "Stage 0: Choose action" "Waiting for the user to select an operation"
    print_menu
    if [[ "$AUTO_YES" == true ]]; then
      if [[ -n "$AUTO_ACTION" ]]; then
        choice="$AUTO_ACTION"
      else
        choice=6
      fi
      case "$choice" in
        1|2|3|4|5|6|7) ;;
        *)
          echo "$(tr "action_invalid" "错误：--action 只能是 1-7 之间的数字。" "Error: --action must be a number from 1 to 7.")" >&2
          exit 1
          ;;
      esac
      log "$(tr "auto_choice" "非交互模式，自动选择菜单项: $choice" "Non-interactive mode; automatically selecting menu item: $choice")"
    elif [ -r /dev/tty ]; then
      read -rp "输入选项编号: " choice </dev/tty
    else
      # non-interactive: try to read from stdin, otherwise default to 6 (exit)
      if ! read -r choice; then
        log "$(tr "stdin_default" "检测到非交互式 stdin，自动选择退出。若要无交互安装，请使用 --yes 参数或在终端运行脚本。" "Detected non-interactive stdin; automatically exiting. For non-interactive installation, use --yes or run the script in a terminal.")"
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
        log "$(tr "exit_message" "已退出。" "Exiting.")"
        exit 0
        ;;
      *)
        echo "$(tr "invalid_choice" "无效输入，请输入 1-7 之间的数字。" "Invalid input. Please enter a number from 1 to 7.")"
        ;;
    esac

    if [[ "$AUTO_YES" == true ]]; then
      log "$(tr "skip_menu_prompt" "非交互模式，跳过返回主菜单提示。" "Non-interactive mode; skipping the return-to-menu prompt.")"
      break
    fi

    if prompt_yes_no "是否返回主菜单继续操作？" "y"; then
      continue
    fi

    log "$(tr "finish_message" "安装与配置完成。" "Installation and configuration are complete.")"
    echo "$(tr "finish_note" "请根据需要检查 ~/.config/niri/config.kdl 中的配置，并在 niri 启动前确认相关服务能够正确运行。" "Please review ~/.config/niri/config.kdl as needed and ensure the required services are running before starting niri.")"
    break
  done
}

main_menu "$@"
