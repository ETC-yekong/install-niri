#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
full_screen_active=0

run_cmd() {
  printf '\n--> %s\n' "$*"
  if ! eval "$*"; then
    echo "Command failed: $*" >&2
    return 1
  fi
}

enter_fullscreen() {
  if command -v tput >/dev/null 2>&1; then
    tput smcup >/dev/null 2>&1 || true
    tput clear >/dev/null 2>&1 || true
    full_screen_active=1
  else
    clear
  fi
}

exit_fullscreen() {
  if [ "$full_screen_active" = 1 ] && command -v tput >/dev/null 2>&1; then
    tput rmcup >/dev/null 2>&1 || true
  fi
}

trap exit_fullscreen EXIT

run_yay() {
  if [ "$(id -u)" -eq 0 ]; then
    if [ -n "${SUDO_USER-}" ]; then
      sudo -u "$SUDO_USER" yay "$@"
    else
      echo "请不要以 root 用户直接运行该脚本。请使用普通用户执行常用软件安装。" >&2
      return 1
    fi
  else
    yay "$@"
  fi
}

install_zsh() {
  printf '\n=== 安装并美化 zsh ===\n'
  run_cmd "sudo pacman -S --needed zsh zsh-completions zsh-syntax-highlighting zsh-autosuggestions starship"
  mkdir -p "$HOME"
  if [ -f "$script_dir/.zshrc" ]; then
    run_cmd "cp \"$script_dir/.zshrc\" \"$HOME/.zshrc\""
  else
    echo ".zshrc 未在脚本目录找到，跳过复制。"
  fi
  mkdir -p "$HOME/.config"
  if [ -f "$script_dir/starship.toml" ]; then
    run_cmd "mkdir -p \"$HOME/.config\" && cp \"$script_dir/starship.toml\" \"$HOME/.config/starship.toml\""
  else
    echo "starship.toml 未在脚本目录找到，跳过复制。"
  fi
  if [ -d "$script_dir/kitty" ]; then
    run_cmd "mkdir -p \"$HOME/.config/kitty\" && cp -r \"$script_dir/kitty\"/* \"$HOME/.config/kitty/\""
  else
    echo "kitty 配置目录未找到，跳过复制。"
  fi
  echo "zsh 安装完成。"
}

install_kvm() {
  printf '\n=== 安装 KVM 虚拟机相关软件 ===\n'
  run_cmd "sudo pacman -S --needed qemu-full virt-manager swtpm dnsmasq"
  run_cmd "sudo systemctl enable --now libvirtd"
  run_cmd "sudo virsh net-start default || true"
  run_cmd "sudo virsh net-autostart default || true"
  run_cmd "sudo usermod -a -G libvirt $(whoami)"
  if [ -f "$script_dir/kvm_intel.conf" ]; then
    run_cmd "sudo cp \"$script_dir/kvm_intel.conf\" /etc/modprobe.d/kvm_intel.conf"
    run_cmd "sudo mkinitcpio -P"
  else
    echo "kvm_intel.conf 未在脚本目录找到，跳过复制与 mkinitcpio。"
  fi
  echo "KVM 相关安装完成。请重新登录以应用用户组变更。"
}

ensure_yay() {
  if command -v yay >/dev/null 2>&1; then
    return 0
  fi

  printf '\n=== 检测到 yay 未安装，尝试从 archlinuxcn 源安装 yay ===\n'
  run_cmd "sudo pacman -S --needed yay"
  if ! command -v yay >/dev/null 2>&1; then
    echo "yay 安装失败，请确保已启用 archlinuxcn 软件源后重试。" >&2
    return 1
  fi
}

install_qq() {
  printf '\n=== 安装 QQ ===\n'
  run_yay -S --needed linuxqq-appimage
}

install_wechat() {
  printf '\n=== 安装 微信 ===\n'
  run_yay -S --needed wechat-universal-bwrap
}

install_wps() {
  printf '\n=== 安装 WPS Office ===\n'
  run_yay -S --needed wps-office-cn wps-mui-zh-cn
}

install_vscode() {
  printf '\n=== 安装 Visual Studio Code ===\n'
  run_yay -S --needed visual-studio-code-bin
}

install_edge() {
  printf '\n=== 安装 Microsoft Edge ===\n'
  run_yay -S --needed microsoft-edge-stable-bin
}

install_lutris() {
  printf '\n=== 安装 Lutris ===\n'
  run_cmd "sudo pacman -S --needed lutris"
}

install_hmcl() {
  printf '\n=== 安装 HMCL ===\n'
  run_cmd "sudo pacman -S --needed hmcl"
}

install_flclash() {
  printf '\n=== 安装 FlClash ===\n'
  run_cmd "sudo pacman -S --needed flclash"
}

install_common_apps() {
  if ! ensure_yay; then
    return 1
  fi

  printf '\n请选择要安装的常用软件（输入序号，空格分隔；输入 0 返回菜单）：\n'
  cat <<EOF
1) QQ (linuxqq-appimage)
2) 微信 (wechat-universal-bwrap)
3) WPS Office (wps-office-cn, wps-mui-zh-cn)
4) VSCode (visual-studio-code-bin)
5) Microsoft Edge (microsoft-edge-stable-bin)
6) Lutris (lutris)
7) HMCL (hmcl)
8) FlClash (flclash)
EOF
  read -r -p "> " selections

  if [ -z "$selections" ] || echo "$selections" | grep -qw "0"; then
    echo "返回主菜单。"
    return 0
  fi

  for item in $selections; do
    case "$item" in
      1)
        install_qq || echo "QQ 安装失败。"
        ;;
      2)
        install_wechat || echo "微信安装失败。"
        ;;
      3)
        install_wps || echo "WPS Office 安装失败。"
        ;;
      4)
        install_vscode || echo "VSCode 安装失败。"
        ;;
      5)
        install_edge || echo "Microsoft Edge 安装失败。"
        ;;
      6)
        install_lutris || echo "Lutris 安装失败。"
        ;;
      7)
        install_hmcl || echo "HMCL 安装失败。"
        ;;
      8)
        install_flclash || echo "FlClash 安装失败。"
        ;;
      *)
        echo "无效选项：$item"
        ;;
    esac
  done
}

show_menu() {
  cat <<EOF

请选择要执行的操作（每项为独立安装条目）：
0) 退出
1) 安装并配置 zsh（包含 starship 与 kitty 配置）
2) 安装 KVM 与相关配置
3) 安装常用软件
4) 显示脚本目录并列出可用的配置文件

输入选项并回车：
EOF
}

list_available() {
  echo "脚本目录： $script_dir"
  echo "可用配置文件："
  for f in .zshrc starship.toml kvm_intel.conf; do
    if [ -e "$script_dir/$f" ]; then
      echo " - $f"
    fi
  done
  if [ -d "$script_dir/kitty" ]; then
    echo " - kitty/ (目录)"
  fi
}

main() {
  enter_fullscreen
  while true; do
    show_menu
    read -r -p "> " choice
    case "$choice" in
      0|q|Q)
        echo "退出。"
        exit 0
        ;;
      1)
        install_zsh || echo "zsh 安装遇到问题。"
        read -r -p "按回车返回菜单..." _
        ;;
      2)
        install_kvm || echo "KVM 安装遇到问题。"
        read -r -p "按回车返回菜单..." _
        ;;
      3)
        install_common_apps || echo "安装常用软件遇到问题。"
        read -r -p "按回车返回菜单..." _
        ;;
      4)
        list_available
        read -r -p "按回车返回菜单..." _
        ;;
      *)
        echo "无效选项：$choice"
        ;;
    esac
  done
}

main "$@"
