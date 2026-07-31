#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_cmd() {
  echo "\n--> $*"
  if ! eval "$*"; then
    echo "Command failed: $*" >&2
    return 1
  fi
}

install_zsh() {
  echo "\n=== 安装并美化 zsh ==="
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
  echo "\n=== 安装 KVM 虚拟机相关软件 ==="
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

show_menu() {
  cat <<EOF

请选择要执行的操作（每项为独立安装条目）：
0) 退出
1) 安装并配置 zsh（包含 starship 与 kitty 配置）
2) 安装 KVM 与相关配置
3) 显示脚本目录并列出可用的配置文件

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
