#!/usr/bin/env bash
#
# power-menu — waybar / キーバインドから呼ぶ電源メニュー
#
#   power-menu.sh            メニューを出す
#
# 再起動・シャットダウン・ログアウトは押し間違えると作業が飛ぶので、
# 確認を 1 枚はさみます（ロックとサスペンドは即実行）。
#
set -uo pipefail

command -v wofi >/dev/null 2>&1 || { echo "wofi がありません" >&2; exit 1; }

menu() {
  local prompt=$1 lines=$2
  wofi --dmenu --insensitive --hide-search --prompt "$prompt" --lines "$lines" --width 320 --cache-file /dev/null
}

confirm() {
  local what=$1 answer
  answer=$(printf 'いいえ\nはい\n' | menu "$what しますか？" 2) || return 1
  [[ $answer == はい ]]
}

lock() {
  pidof hyprlock >/dev/null 2>&1 || hyprlock &
}

logout() {
  # hyprshutdown があればそちらに任せる（setup.sh で入れている AUR パッケージ）
  if command -v hyprshutdown >/dev/null 2>&1; then
    hyprshutdown
  else
    hyprctl dispatch 'hl.dsp.exit()'
  fi
}

# 休止は swap が無いとできません。この dotfiles は zram swap なので、
# 普通は使えません（zram に退避しても電源を切ると消えるため）。
# ちゃんとした swap パーティション / swapfile があるときだけ項目を出します。
hibernate_ok() {
  grep -q disk /sys/power/state 2>/dev/null || return 1
  awk 'NR > 1 && $1 !~ /^\/dev\/zram/ { found = 1 } END { exit !found }' /proc/swaps 2>/dev/null
}

entries='󰌾  ロック
󰒲  サスペンド'
hibernate_ok && entries+='
󰖔  休止 (hibernate)'
entries+='
󰍃  ログアウト
󰜉  再起動
󰐥  シャットダウン'

lines=$(printf '%s\n' "$entries" | wc -l)
choice=$(printf '%s\n' "$entries" | menu "電源" "$lines") || exit 0
[[ -z $choice ]] && exit 0

case "$choice" in
  *ロック*)       lock ;;
  *サスペンド*)   lock; systemctl suspend ;;
  *休止*)         confirm "休止" && systemctl hibernate ;;
  *ログアウト*)   confirm "ログアウト" && logout ;;
  *再起動*)       confirm "再起動" && systemctl reboot ;;
  *シャットダウン*) confirm "シャットダウン" && systemctl poweroff ;;
esac
