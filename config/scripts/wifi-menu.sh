#!/usr/bin/env bash
#
# wifi-menu — waybar のネットワークモジュールから呼ぶ Wi-Fi メニュー
#
#   wifi-menu.sh          メニューを出す（一覧から選んで接続 / ON・OFF 切り替え）
#   wifi-menu.sh toggle   メニューを出さずに Wi-Fi の ON/OFF だけ切り替える
#
# NetworkManager (nmcli) と wofi が必要です。どちらも setup.sh で入ります。
# パスワードが必要なネットワークは wofi のパスワード入力で聞きます。
#
set -uo pipefail

notify() {
  command -v notify-send >/dev/null 2>&1 && notify-send -a "Wi-Fi" "$@" || echo "$*"
}

command -v nmcli >/dev/null 2>&1 || { notify "nmcli がありません" "networkmanager を入れてください"; exit 1; }

# wofi の dmenu 呼び出し。--password を付けるとパスワード入力欄になります。
menu() {
  local prompt=$1; shift
  wofi --dmenu --insensitive --prompt "$prompt" --lines 10 --width 460 \
       --cache-file /dev/null "$@"
}

radio_state() { nmcli -t radio wifi 2>/dev/null; }

toggle_radio() {
  if [[ $(radio_state) == enabled ]]; then
    nmcli radio wifi off && notify "Wi-Fi を OFF にしました"
  else
    nmcli radio wifi on && notify "Wi-Fi を ON にしました"
  fi
}

# 既に保存済みの接続かどうか
is_saved() {
  nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$1"
}

connect_ssid() {
  local ssid=$1 security=$2

  if is_saved "$ssid"; then
    # 保存済みならパスワードは聞かない
    if nmcli connection up id "$ssid" >/dev/null 2>&1; then
      notify "接続しました" "$ssid"
      return 0
    fi
    # 保存されたパスワードが古い場合などはここに落ちるので、聞き直す
    notify "保存された設定では繋がりませんでした" "$ssid — パスワードを聞き直します"
  fi

  local pass=""
  if [[ -n $security && $security != "--" && $security != "なし" ]]; then
    # wofi --dmenu は stdin を読み切るまで待つので、パスワード入力では空を流し込む
    pass=$(menu "$ssid のパスワード" --password </dev/null) || return 1
    [[ -z $pass ]] && return 1
  fi

  local out rc
  if [[ -n $pass ]]; then
    out=$(nmcli device wifi connect "$ssid" password "$pass" 2>&1); rc=$?
  else
    out=$(nmcli device wifi connect "$ssid" 2>&1); rc=$?
  fi

  if (( rc == 0 )); then
    notify "接続しました" "$ssid"
  else
    notify "接続できませんでした" "$ssid: ${out##*: }"
  fi
}

case "${1:-menu}" in
  toggle) toggle_radio; exit 0 ;;
  menu)   ;;
  *)      echo "使い方: ${0##*/} [menu|toggle]" >&2; exit 1 ;;
esac

command -v wofi >/dev/null 2>&1 || { notify "wofi がありません"; exit 1; }

if [[ $(radio_state) != enabled ]]; then
  # OFF のときは ON にするかどうかだけ聞く
  choice=$(printf '󰖩  Wi-Fi を ON にする\n󰅖  閉じる\n' | menu "Wi-Fi: OFF") || exit 0
  [[ $choice == *"ON にする"* ]] && toggle_radio
  exit 0
fi

# 一覧を作る。rescan は少し時間がかかるので no でキャッシュを使い、
# 明示的に「再スキャン」を選んだときだけ待たせます。
list_networks() {
  local rescan=${1:-no}
  # --escape no で SSID 中の ":" がエスケープされないようにし、
  # SSID 自体に ":" が入っていても壊れないよう 4 列目以降をまとめて取ります。
  nmcli --terse --escape no --fields IN-USE,SIGNAL,SECURITY,SSID \
    device wifi list --rescan "$rescan" 2>/dev/null |
    awk -F: '{
      ssid = $0
      sub(/^[^:]*:[^:]*:[^:]*:/, "", ssid)
      if (ssid == "" || seen[ssid]++) next
      mark = ($1 == "*") ? "󰄬" : " "
      sec  = ($3 == "" || $3 == "--") ? "󰌾なし" : "󰌾" $3
      printf "%s  %s  (%s%%, %s)\n", mark, ssid, $2, sec
    }'
}

rescan=no
while :; do
  networks=$(list_networks "$rescan")
  rescan=no

  entries=$(printf '%s\n󰑐  再スキャン\n󰖪  Wi-Fi を OFF にする\n󰒓  詳細設定 (nmtui)\n' "$networks")
  choice=$(printf '%s' "$entries" | menu "Wi-Fi") || exit 0
  [[ -z $choice ]] && exit 0

  case "$choice" in
    *"再スキャン"*)        rescan=yes; continue ;;
    *"OFF にする"*)        toggle_radio; exit 0 ;;
    *"nmtui"*)             exec foot -e nmtui ;;
  esac

  # "󰄬  SSID  (72%, 󰌾WPA2)" から SSID と暗号化の有無を取り出す。
  # 接続中マークが付かない行は先頭が空白なので、まとめて落とします。
  ssid=$(printf '%s' "$choice" | sed -E 's/^[^ ]*[[:space:]]+//; s/[[:space:]]+\([0-9]+%,[^)]*\)$//')
  security=$(printf '%s' "$choice" | sed -E 's/.*, 󰌾([^)]*)\)$/\1/')
  [[ -z $ssid ]] && exit 0

  connect_ssid "$ssid" "$security"
  exit 0
done
