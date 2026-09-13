#!/usr/bin/env bash
#
# mail-hidden — Thunderbird をメール用スクラッチパッドに隠したまま起動する
#
# hyprland.lua のウィンドウルールで special:mail には入るのですが、Lua の
# window_rule には silent フィールドが無いため（hyprctl eval で
# "unknown field 'silent'" が返ります）、ルールだけだと開いた瞬間に
# スクラッチパッドが画面に出てしまいます。
# そこでウィンドウが現れるのを待ってから、1 回だけ閉じます。
#
# 表示 / 非表示の切り替えは SUPER + M です。
#
set -uo pipefail

WS="special:mail"
CLASS="[Tt]hunderbird"

for cmd in thunderbird hyprctl jq; do
  command -v "$cmd" >/dev/null 2>&1 || exit 0
done

# 既に動いていれば二重に起動しない
pgrep -x thunderbird >/dev/null 2>&1 || thunderbird >/dev/null 2>&1 &

# ウィンドウが現れるまで待つ（最大 60 秒）。メールの初回同期は遅いので長めに取ります。
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
  hyprctl dispatch 'hl.dsp.workspace.toggle_special("mail")' >/dev/null
fi
