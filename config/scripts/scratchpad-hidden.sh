#!/usr/bin/env bash
#
# scratchpad-hidden — 指定したアプリをスクラッチパッドに隠したまま起動する
#
#   scratchpad-hidden.sh <special ws 名> <pgrep -x 用プロセス名> <class の一部> <起動コマンド...>
#
# hyprland.lua のウィンドウルールで special:<name> には入るのですが、Lua の
# window_rule には silent フィールドが無いため（hyprctl eval で
# "unknown field 'silent'" が返ります）、ルールだけだと開いた瞬間に
# スクラッチパッドが画面に出てしまいます。
# そこでウィンドウが現れるのを待ってから、1 回だけ閉じます。
#
# 同じ special ws に複数アプリを入れる場合はアプリごとにこのスクリプトを
# 呼んでください（例: メールと Slack を同じ special:mail に入れる）。
#
set -uo pipefail

NAME=$1 PROC=$2 CLASS=$3
shift 3
WS="special:$NAME"

for cmd in hyprctl jq; do
  command -v "$cmd" >/dev/null 2>&1 || exit 0
done
command -v "$1" >/dev/null 2>&1 || exit 0

# 既に動いていれば二重に起動しない
pgrep -x "$PROC" >/dev/null 2>&1 || "$@" >/dev/null 2>&1 &

# ウィンドウが現れるまで待つ（最大 60 秒）。初回起動・同期は遅いことがあるので長めに取ります。
for _ in $(seq 120); do
  if hyprctl clients -j 2>/dev/null |
       jq -e --arg c "$CLASS" 'any(.[]; .class | test($c))' >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

# 配置が落ち着くのを待つ
sleep 1

# トグルなので、出ていないときに叩くと逆に開いてしまいます。
# いま表示されている場合だけ閉じます。
if hyprctl monitors -j 2>/dev/null |
     jq -e --arg w "$WS" 'any(.[]; .specialWorkspace.name == $w)' >/dev/null 2>&1; then
  hyprctl dispatch "hl.dsp.workspace.toggle_special(\"$NAME\")" >/dev/null
fi
