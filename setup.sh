#!/usr/bin/env bash
#
# ThinkPad X1 Carbon Gen 7 — EndeavourOS / Arch 用 Hyprland セットアップ
#
# 前提:
#   - EndeavourOS（または Arch）インストール済み、ネットワーク接続済み
#   - 一般ユーザー（wheel グループ）で実行すること
#
# 実行:
#   chmod +x setup.sh && ./setup.sh
#
# 何度実行しても壊れないように書いてあります。途中で失敗しても、
# 直してからもう一度流せば続きから整います。
#
set -uo pipefail

# ---------------------------------------------------------------- 共通

C_INFO='\033[1;34m'; C_WARN='\033[1;33m'; C_OK='\033[1;32m'; C_ERR='\033[1;31m'; C_OFF='\033[0m'
info() { echo -e "${C_INFO}==>${C_OFF} $*"; }
warn() { echo -e "${C_WARN}warn:${C_OFF} $*"; }
ok()   { echo -e "${C_OK}ok:${C_OFF} $*"; }
die()  { echo -e "${C_ERR}error:${C_OFF} $*" >&2; exit 1; }

FAILED_PKGS=()
NOTES=()

ask() {
  local reply
  read -rp "$(echo -e "${C_INFO}?${C_OFF}") $1 [y/N] " reply
  [[ ${reply,,} == y || ${reply,,} == yes ]]
}

# pac: 必須パッケージ。まとめて入らなければ 1 個ずつ試して、
#      入らなかったものを記録する。1 つのタイプミスで全部止まらないようにするため。
pac() {
  if sudo pacman -S --needed --noconfirm "$@" >/dev/null; then
    return 0
  fi
  warn "まとめてのインストールに失敗しました。1 つずつ試します。"
  local p
  for p in "$@"; do
    if ! sudo pacman -S --needed --noconfirm "$p" >/dev/null 2>&1; then
      warn "  入りませんでした: $p"
      FAILED_PKGS+=("$p")
    fi
  done
}

# pac_opt: 無くても致命的でないもの
pac_opt() {
  local p
  for p in "$@"; do
    sudo pacman -S --needed --noconfirm "$p" >/dev/null 2>&1 || warn "  省略: $p (リポジトリに無い)"
  done
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- 事前チェック

[[ $EUID -eq 0 ]] && die "root では実行しないでください。"
have pacman || die "Arch 系ではないようです。"

IS_EOS=false
if [[ -f /etc/os-release ]] && grep -qi endeavour /etc/os-release; then
  IS_EOS=true
  ok "EndeavourOS を検出しました。"
else
  info "Arch (非 EndeavourOS) として進めます。"
fi

if ! grep -qi "X1 Carbon" /sys/devices/virtual/dmi/id/product_family 2>/dev/null; then
  warn "X1 Carbon として認識されませんでした。ThinkPad 固有の設定は不適切かもしれません。"
  ask "続行しますか？" || exit 1
fi

info "sudo の認証を先に済ませます。"
sudo -v || die "sudo に失敗しました。"
# バックグラウンドで sudo タイムスタンプを維持（親が死んだら終了）
( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null || true' EXIT

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# ---------------------------------------------------------------- pacman 設定

info "pacman の設定を調整します（並列DL、色）"
sudo sed -i \
  -e 's/^#Color/Color/' \
  -e 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' \
  /etc/pacman.conf
grep -q '^ILoveCandy' /etc/pacman.conf || \
  sudo sed -i '/^ParallelDownloads/a ILoveCandy' /etc/pacman.conf

info "ミラーを日本優先に並べ替えます"
pac reflector
sudo reflector --country Japan --age 12 --protocol https --sort rate \
  --save /etc/pacman.d/mirrorlist || warn "reflector に失敗しました。既存のミラーで続行します。"

if $IS_EOS && have eos-rankmirrors; then
  # EndeavourOS 独自リポジトリのミラーは reflector の管轄外なので別で並べ替える
  sudo eos-rankmirrors --once >/dev/null 2>&1 || warn "eos-rankmirrors をスキップしました。"
fi

info "システムを更新します（ここは時間がかかります）"
sudo pacman -Syu --noconfirm || die "システム更新に失敗しました。ミラー / ネットワークを確認してください。"

# ---------------------------------------------------------------- 基本ツール

info "基本ツールを導入します"
pac \
  base-devel git curl wget rsync \
  zsh tmux neovim \
  fd ripgrep fzf bat eza jq \
  htop btop \
  unzip p7zip \
  openssh \
  reflector pacman-contrib \
  xdg-user-dirs imagemagick

# 日本語のディレクトリ名は端末で扱いづらいので英語のまま作る
LC_ALL=C xdg-user-dirs-update --force >/dev/null 2>&1 || true

sudo systemctl enable --now paccache.timer >/dev/null 2>&1 \
  || warn "paccache.timer を有効化できませんでした。"

# ---------------------------------------------------------------- AUR ヘルパ

# EndeavourOS には yay が最初から入っています。paru も Arch の extra にあります。
# 無ければ AUR からビルドする、の順で探します。
if have paru; then
  AUR_HELPER=paru
elif have yay; then
  AUR_HELPER=yay
elif sudo pacman -S --needed --noconfirm paru >/dev/null 2>&1; then
  AUR_HELPER=paru
else
  info "paru（AUR ヘルパ）を AUR からビルドします"
  tmp=$(mktemp -d)
  if git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin" \
     && (cd "$tmp/paru-bin" && makepkg -si --noconfirm); then
    AUR_HELPER=paru
  else
    AUR_HELPER=""
    warn "AUR ヘルパを用意できませんでした。AUR パッケージはスキップします。"
  fi
  rm -rf "$tmp"
fi
[[ -n $AUR_HELPER ]] && ok "AUR ヘルパ: $AUR_HELPER"

# ---------------------------------------------------------------- グラフィック

info "Intel UHD 620 向けのグラフィックスタックを導入します"
pac mesa vulkan-intel intel-media-driver libva-utils vulkan-tools
# 古い i965 ドライバ。Gen9 では iHD を使うので必須ではないが、
# 一部の古いアプリのフォールバックとして入れておく
pac_opt libva-intel-driver

# LIBVA_DRIVER_NAME は hyprland.lua の hl.env で設定しています。
# /etc/environment.d/ は systemd ユーザーサービスにしか効かず、
# TTY から起動した Hyprland には伝わらないため、そちらには置きません。

# ---------------------------------------------------------------- オーディオ

info "PipeWire を導入します"
pac pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
    sof-firmware alsa-utils pavucontrol

# pipewire は socket activation で自動起動するので enable は基本不要。
# 明示的に有効化しておくが、失敗しても止めない。
systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1 \
  || warn "PipeWire のユーザーユニット有効化をスキップしました（再ログイン後に自動で起動します）。"

# ---------------------------------------------------------------- ネットワーク / BT

info "ネットワークと Bluetooth"
pac networkmanager network-manager-applet bluez bluez-utils blueman
sudo systemctl enable --now NetworkManager >/dev/null 2>&1 || warn "NetworkManager の有効化に失敗。"
sudo systemctl enable --now bluetooth      >/dev/null 2>&1 || warn "bluetooth の有効化に失敗。"

# ---------------------------------------------------------------- 電源管理

info "電源管理（TLP）を設定します"

# power-profiles-daemon と TLP は排他。EndeavourOS のデスクトップ版には
# 最初から入っていることが多いので、あれば外す。
if pacman -Qq power-profiles-daemon &>/dev/null; then
  warn "power-profiles-daemon を削除します（TLP と競合するため）"
  sudo systemctl disable --now power-profiles-daemon.service >/dev/null 2>&1 || true
  sudo pacman -Rns --noconfirm power-profiles-daemon >/dev/null 2>&1 \
    || warn "削除できませんでした（何かが依存しています）。TLP は入れずに終わります。"
fi

if pacman -Qq power-profiles-daemon &>/dev/null; then
  warn "power-profiles-daemon が残っているため TLP はスキップします。"
  NOTES+=("TLP を入れていません。power-profiles-daemon を手動で外してから再実行してください。")
else
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

  sudo systemctl enable --now tlp.service      >/dev/null 2>&1 || warn "tlp の有効化に失敗。"
  sudo systemctl enable --now thermald.service >/dev/null 2>&1 || warn "thermald の有効化に失敗。"
  sudo systemctl mask systemd-rfkill.service systemd-rfkill.socket >/dev/null 2>&1 || true
fi

# --- zram（swap パーティションの代わり）
info "zram swap を設定します"
pac zram-generator
sudo tee /etc/systemd/zram-generator.conf >/dev/null <<'ZRAM'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
ZRAM
sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service >/dev/null 2>&1 \
  || warn "zram は再起動後に有効になります。"

# ---------------------------------------------------------------- Hyprland

info "Hyprland と周辺ツールを導入します"
pac \
  hyprland \
  xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  hypridle hyprlock hyprpaper hyprpicker hyprpolkitagent \
  waybar wofi swaync \
  foot \
  grim slurp wl-clipboard cliphist \
  brightnessctl playerctl \
  thunar thunar-volman gvfs tumbler \
  qt5-wayland qt6-wayland qt6ct \
  polkit \
  firefox

# hyprland-qtutils / hyprland-guiutils が無いと Hyprland が起動時に警告を出します
pac_opt hyprland-qtutils hyprland-guiutils hyprshutdown hyprlauncher

# --- Hyprland のバージョン確認（ここが今回いちばん大事）
HYPR_VER=$(Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[[ -z ${HYPR_VER:-} ]] && HYPR_VER=$(hyprctl version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

if [[ -n ${HYPR_VER:-} ]]; then
  ok "Hyprland ${HYPR_VER}"
  HYPR_MINOR=$(cut -d. -f2 <<<"$HYPR_VER")
  HYPR_MAJOR=$(cut -d. -f1 <<<"$HYPR_VER")
  if (( HYPR_MAJOR == 0 && HYPR_MINOR < 55 )); then
    warn "この設定は Hyprland 0.55 以降の Lua 設定です。"
    warn "0.55 未満では hyprland.lua は読まれず、設定なしで起動します。"
    NOTES+=("Hyprland が ${HYPR_VER} です。sudo pacman -Syu で 0.55 以降に上げてください。")
  fi
else
  warn "Hyprland のバージョンを取得できませんでした。"
fi

# ---------------------------------------------------------------- フォント / IME

info "フォントと日本語入力を導入します"
pac \
  noto-fonts noto-fonts-cjk noto-fonts-emoji \
  ttf-jetbrains-mono-nerd ttf-firacode-nerd \
  fcitx5 fcitx5-configtool fcitx5-gtk fcitx5-qt fcitx5-mozc

pac_opt papirus-icon-theme

# 入力メソッドの環境変数は hyprland.lua の hl.env に集約しています。
# （/etc/environment.d/ は Hyprland を TTY から起動した場合に効きません）

# ---------------------------------------------------------------- 壁紙

WALLDIR="$HOME/Pictures/wallpapers"
mkdir -p "$WALLDIR"
if [[ ! -f "$WALLDIR/wall.png" ]]; then
  info "壁紙を生成します（好きな画像に差し替えてください: $WALLDIR/wall.png）"
  MAGICK=""
  have magick && MAGICK="magick"
  [[ -z $MAGICK ]] && have convert && MAGICK="convert"
  if [[ -n $MAGICK ]]; then
    $MAGICK -size 3840x2160 \
      gradient:'#1a1b26-#292e42' \
      -swirl 20 \
      "$WALLDIR/wall.png" 2>/dev/null \
      || $MAGICK -size 3840x2160 gradient:'#1a1b26-#292e42' "$WALLDIR/wall.png"
    ok "$WALLDIR/wall.png"
  else
    warn "ImageMagick が無いため壁紙を生成できませんでした。"
    NOTES+=("$WALLDIR/wall.png に好きな画像を置いてください（無いと壁紙が出ません）。")
  fi
fi

# ---------------------------------------------------------------- 設定ファイル配置

deploy() {
  # deploy <リポジトリ内の相対パス> <配置先>
  local src="$SCRIPT_DIR/config/$1" dst="$2"
  [[ -e $src ]] || { warn "見つかりません: $src"; return; }
  mkdir -p "$(dirname "$dst")"
  if [[ -e $dst && ! -L $dst ]]; then
    local bak="$dst.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$dst" "$bak"
    warn "既存を退避: $bak"
  fi
  cp -r "$src" "$dst"
  ok "$dst"
}

info "設定ファイルを配置します"
deploy hypr/hyprland.lua   "$HOME/.config/hypr/hyprland.lua"
deploy hypr/hypridle.conf  "$HOME/.config/hypr/hypridle.conf"
deploy hypr/hyprlock.conf  "$HOME/.config/hypr/hyprlock.conf"
deploy hypr/hyprpaper.conf "$HOME/.config/hypr/hyprpaper.conf"
deploy waybar/config.jsonc "$HOME/.config/waybar/config.jsonc"
deploy waybar/style.css    "$HOME/.config/waybar/style.css"
deploy wofi/config         "$HOME/.config/wofi/config"
deploy wofi/style.css      "$HOME/.config/wofi/style.css"
deploy foot/foot.ini       "$HOME/.config/foot/foot.ini"
deploy swaync/config.json  "$HOME/.config/swaync/config.json"
deploy swaync/style.css    "$HOME/.config/swaync/style.css"

# 0.54 以前の設定が残っていると紛らわしいので退避する
if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
  mv "$HOME/.config/hypr/hyprland.conf" "$HOME/.config/hypr/hyprland.conf.old"
  warn "古い hyprland.conf を hyprland.conf.old に退避しました（0.55+ では .lua が使われます）。"
fi

# ---------------------------------------------------------------- 検証

info "設定を検証します"

if have waybar; then
  # 設定 JSON が壊れているとバーが一切出ないので、ここで弾く
  # jsonc なので行コメントを落としてから jq に食わせる
  if sed 's|^[[:space:]]*//.*$||' "$HOME/.config/waybar/config.jsonc" | jq empty 2>/dev/null; then
    ok "waybar の設定は JSON として妥当です。"
  else
    warn "waybar の設定に JSON エラーがあります。バーが出ない原因になります。"
  fi
fi

for f in hypridle.conf hyprlock.conf hyprpaper.conf; do
  [[ -f "$HOME/.config/hypr/$f" ]] || warn "$f がありません。"
done

if have hyprlock; then
  # hyprlock は設定が無いとエラー終了する。あることだけ確認しておく。
  ok "hyprlock の設定を配置済み（ロックできないときは 'hyprlock -v' でログを見てください）。"
fi

# ---------------------------------------------------------------- 仕上げ

echo
if (( ${#FAILED_PKGS[@]} )); then
  warn "インストールできなかったパッケージ: ${FAILED_PKGS[*]}"
  echo "  名前が変わっている / AUR にある可能性があります。"
  echo "  検索: pacman -Ss <名前>   /   ${AUR_HELPER:-paru} -Ss <名前>"
  echo
fi

if (( ${#NOTES[@]} )); then
  warn "確認してほしいこと:"
  for n in "${NOTES[@]}"; do echo "  - $n"; done
  echo
fi

info "導入が完了しました。以下を確認してください。"
cat <<'OUTRO'

  1. バッテリーの劣化状況
     upower -i /org/freedesktop/UPower/devices/battery_BAT0

     energy-full が 35Wh を切っていれば交換推奨（設計値 51Wh、型番 02DL004）

  2. 充電しきい値が効いているか
     cat /sys/class/power_supply/BAT0/charge_control_{start,end}_threshold

  3. オーディオ
     wpctl status     # sof-firmware が効いていればデバイスが見える

  4. ファームウェア更新
     fwupdmgr refresh && fwupdmgr get-updates

  5. C-state の落ち込み（バッテリー持ちの主因になりうる）
     sudo powertop     # Idle Stats で C8/C9/C10 に時間が入っていれば正常

  起動は TTY から:

     start-hyprland

  ※ 0.53 以降は `Hyprland` を直接叩くのではなく `start-hyprland` が正式な入口です。
     直接叩くと misc の watchdog 警告が出ます。

  設定でエラーが出たら:

     hyprctl reload            # 設定の再読み込み（エラーがあればポップアップで出る）
     tail -f $XDG_RUNTIME_DIR/hypr/*/hyprland.log

OUTRO

ask "今すぐ再起動しますか？" && sudo reboot
