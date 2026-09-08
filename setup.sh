#!/usr/bin/env bash
#
# ThinkPad X1 Carbon Gen 7 — Arch Linux 初回起動後セットアップ
#
# 前提:
#   - ベースシステム導入済み、ネットワーク接続済み
#   - 一般ユーザー（wheel グループ）で実行すること
#
# 実行:
#   chmod +x setup.sh && ./setup.sh
#
set -euo pipefail

# ---------------------------------------------------------------- 共通

C_INFO='\033[1;34m'; C_WARN='\033[1;33m'; C_OK='\033[1;32m'; C_OFF='\033[0m'
info() { echo -e "${C_INFO}==>${C_OFF} $*"; }
warn() { echo -e "${C_WARN}warn:${C_OFF} $*"; }
ok()   { echo -e "${C_OK}ok:${C_OFF} $*"; }

ask() {
  # ask "質問"  -> yes なら 0
  local reply
  read -rp "$(echo -e "${C_INFO}?${C_OFF}") $1 [y/N] " reply
  [[ ${reply,,} == y || ${reply,,} == yes ]]
}

pac() {
  sudo pacman -S --needed --noconfirm "$@"
}

# ---------------------------------------------------------------- 事前チェック

[[ $EUID -eq 0 ]] && { echo "root では実行しないでください。"; exit 1; }
command -v pacman >/dev/null || { echo "Arch 系ではないようです。"; exit 1; }

if ! grep -qi "X1 Carbon" /sys/devices/virtual/dmi/id/product_family 2>/dev/null; then
  warn "X1 Carbon として認識されませんでした。ThinkPad 固有の設定は不適切かもしれません。"
  ask "続行しますか？" || exit 1
fi

info "sudo の認証を先に済ませます。"
sudo -v
# バックグラウンドで sudo タイムスタンプを維持
while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null || true' EXIT

# ---------------------------------------------------------------- pacman 設定

info "pacman の設定を調整します（並列DL、色、ProgressBar）"
sudo sed -i \
  -e 's/^#Color/Color/' \
  -e 's/^#ParallelDownloads.*/ParallelDownloads = 5/' \
  /etc/pacman.conf
grep -q '^ILoveCandy' /etc/pacman.conf || \
  sudo sed -i '/^ParallelDownloads/a ILoveCandy' /etc/pacman.conf

info "ミラーを日本優先に並べ替えます"
pac reflector
sudo reflector --country Japan --age 12 --protocol https --sort rate \
  --save /etc/pacman.d/mirrorlist

sudo pacman -Syu --noconfirm

# ---------------------------------------------------------------- 基本ツール

info "基本ツールを導入します"
pac \
  base-devel git curl wget rsync \
  zsh tmux neovim \
  fd ripgrep fzf bat eza jq \
  htop btop \
  unzip p7zip \
  openssh \
  reflector pacman-contrib

# pacman キャッシュの定期削除
sudo systemctl enable --now paccache.timer

# ---------------------------------------------------------------- AUR ヘルパ

if ! command -v paru >/dev/null; then
  info "paru（AUR ヘルパ）をビルドします"
  tmp=$(mktemp -d)
  git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
  (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
  rm -rf "$tmp"
fi
ok "paru: $(paru --version | head -1)"

# ---------------------------------------------------------------- グラフィック

info "Intel UHD 620 向けのグラフィックスタックを導入します"
pac \
  mesa vulkan-intel intel-media-driver libva-utils vulkan-tools \
  libva-intel-driver

# VA-API のドライバ指定。Gen9 は iHD（intel-media-driver）を使う
echo 'LIBVA_DRIVER_NAME=iHD' | sudo tee /etc/environment.d/10-va.conf >/dev/null

# ---------------------------------------------------------------- オーディオ

info "PipeWire を導入します"
pac \
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
  sof-firmware alsa-utils pavucontrol

systemctl --user enable pipewire pipewire-pulse wireplumber

# ---------------------------------------------------------------- ネットワーク / BT

info "ネットワークと Bluetooth"
pac networkmanager network-manager-applet bluez bluez-utils blueman
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth

# ---------------------------------------------------------------- 電源管理

info "電源管理（TLP）を設定します"

# power-profiles-daemon と TLP は排他。入っていれば外す
if pacman -Qq power-profiles-daemon &>/dev/null; then
  warn "power-profiles-daemon を削除します（TLP と競合するため）"
  sudo systemctl disable --now power-profiles-daemon.service || true
  sudo pacman -Rns --noconfirm power-profiles-daemon
fi

pac tlp tlp-rdw thermald powertop upower fwupd acpi

sudo tee /etc/tlp.d/01-x1c7.conf >/dev/null <<'TLPCONF'
# ThinkPad X1 Carbon Gen 7 (Whiskey Lake / UHD 620)

# --- CPU -------------------------------------------------------
CPU_DRIVER_OPMODE_ON_AC=active
CPU_DRIVER_OPMODE_ON_BAT=active
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=power
CPU_BOOST_ON_AC=1
CPU_BOOST_ON_BAT=0
# バッテリー時は Turbo を切る。体感差は小さく、消費は目に見えて下がる

PLATFORM_PROFILE_ON_AC=balanced
PLATFORM_PROFILE_ON_BAT=low-power

# --- GPU -------------------------------------------------------
INTEL_GPU_MIN_FREQ_ON_AC=300
INTEL_GPU_MIN_FREQ_ON_BAT=300
INTEL_GPU_BOOST_FREQ_ON_BAT=700

# --- ディスク / PCIe -------------------------------------------
DISK_APM_LEVEL_ON_AC="254 254"
DISK_APM_LEVEL_ON_BAT="128 128"
PCIE_ASPM_ON_AC=default
PCIE_ASPM_ON_BAT=powersupersave
RUNTIME_PM_ON_BAT=auto

# --- 無線 ------------------------------------------------------
WIFI_PWR_ON_AC=off
WIFI_PWR_ON_BAT=on

# --- USB -------------------------------------------------------
USB_AUTOSUSPEND=1
# 外付けマウスやオーディオI/Fが切れる場合は該当 ID を除外する
# USB_DENYLIST="1234:5678"

# --- 充電しきい値 ----------------------------------------------
# Gen 7 は thinkpad_acpi が対応済み。acpi_call は不要。
# 据え置き利用が多いなら 60/80。持ち出しが多いなら 75/95 に上げる。
START_CHARGE_THRESH_BAT0=60
STOP_CHARGE_THRESH_BAT0=80
TLPCONF

sudo systemctl enable --now tlp.service
sudo systemctl enable --now thermald.service
sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket 2>/dev/null || true

# --- zram（swap パーティションの代わり）
info "zram swap を設定します"
pac zram-generator
sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'ZRAM'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
ZRAM

# ---------------------------------------------------------------- Hyprland

info "Hyprland と周辺ツールを導入します"
pac \
  hyprland \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  hypridle hyprlock hyprpaper hyprpicker hyprpolkitagent \
  waybar wofi swaync \
  foot \
  grim slurp wl-clipboard cliphist \
  brightnessctl playerctl pamixer \
  thunar thunar-volman gvfs tumbler \
  qt5-wayland qt6-wayland

# ---------------------------------------------------------------- フォント / IME

info "フォントと日本語入力を導入します"
pac \
  noto-fonts noto-fonts-cjk noto-fonts-emoji \
  ttf-jetbrains-mono-nerd ttf-firacode-nerd \
  fcitx5-im fcitx5-mozc

sudo tee /etc/environment.d/20-im.conf >/dev/null <<'IMCONF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
IMCONF
# Wayland ネイティブなアプリは text-input-v3 を使うので GTK_IM_MODULE は
# 本来不要だが、XWayland 経由のアプリのために残している

# ---------------------------------------------------------------- 設定ファイル配置

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ -f "$SCRIPT_DIR/hyprland.conf" ]]; then
  mkdir -p ~/.config/hypr
  if [[ -e ~/.config/hypr/hyprland.conf ]]; then
    warn "既存の hyprland.conf を .bak に退避します"
    mv ~/.config/hypr/hyprland.conf ~/.config/hypr/hyprland.conf.bak
  fi
  cp "$SCRIPT_DIR/hyprland.conf" ~/.config/hypr/hyprland.conf
  ok "~/.config/hypr/hyprland.conf を配置しました"
fi

# ---------------------------------------------------------------- 仕上げ

echo
info "導入が完了しました。以下を確認してください。"
echo
echo "  1. バッテリーの劣化状況"
echo "     upower -i /org/freedesktop/UPower/devices/battery_BAT0"
echo
echo "     energy-full が 35Wh を切っていれば交換推奨（設計値 51Wh、型番 02DL004）"
echo
echo "  2. 充電しきい値が効いているか"
echo "     cat /sys/class/power_supply/BAT0/charge_control_{start,end}_threshold"
echo
echo "  3. オーディオ"
echo "     wpctl status     # sof-firmware が効いていればデバイスが見える"
echo
echo "  4. ファームウェア更新"
echo "     fwupdmgr refresh && fwupdmgr get-updates"
echo
echo "  5. C-state の落ち込み（バッテリー持ちの主因になりうる）"
echo "     sudo powertop     # Idle Stats で C8/C9/C10 に時間が入っていれば正常"
echo
warn "再起動後、TTY から 'Hyprland' で起動します。"
warn "画面がちらつく場合は、カーネルパラメータの i915.enable_psr を 0 にしてください。"
echo
ask "今すぐ再起動しますか？" && sudo reboot
