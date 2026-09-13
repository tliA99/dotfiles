#!/usr/bin/env bash
#
# birdtray-theme — Birdtray のトレイアイコンを Tokyo Night に合わせる
#
# Birdtray は既定だと未読数を数字でアイコンに描きます。このスクリプトは
# それをやめて、色だけで知らせる形にします。
#
#   未読なし … 灰 (#565f89) の封筒
#   未読あり … 青 (#7aa2f7) の封筒
#
# 監視するアカウント（フォルダ）の設定は Birdtray の設定画面でしか行えません。
# そのためこのスクリプトは設定ファイルを上書きせず、必要なキーだけ差し込みます。
# 先に一度 Birdtray を起動してアカウントを設定しておいてください。
#
#   使い方: birdtray-theme.sh
#
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/birdtray-config.json"
ICON_READ_COLOR="#565f89"
ICON_UNREAD_COLOR="#7aa2f7"

die() { echo "エラー: $*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 がありません。"
command -v jq      >/dev/null 2>&1 || die "jq がありません。"

if [[ ! -f $CONFIG ]]; then
  cat >&2 <<'MSG'
エラー: Birdtray の設定ファイルが見つかりません。

  まず birdtray を一度起動し、設定画面で監視するフォルダ（アカウント）を
  選んでから、もう一度このスクリプトを実行してください。
  設定が書かれていない状態でこちらから作ると、監視間隔などの既定値が
  すべて 0 になってしまうため、あえて作らないようにしています。
MSG
  exit 1
fi

jq empty "$CONFIG" 2>/dev/null || die "$CONFIG が JSON として壊れています。"

# Birdtray は終了時にも設定を書き出すので、動いていたら一旦止めます。
BIRDTRAY_WAS_RUNNING=false
if pgrep -x birdtray >/dev/null 2>&1; then
  BIRDTRAY_WAS_RUNNING=true
  pkill -x birdtray || true
  # 終了時の書き出しを待つ（待たないとこちらの変更が上書きされます）
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x birdtray >/dev/null 2>&1 || break
    sleep 0.3
  done
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- アイコンを作る（ImageMagick は使わず、zlib だけで PNG を組む）
cat > "$tmp/gen.py" <<'PY'
import sys, zlib, struct

SIZE = 64
BG = (0x1a, 0x1b, 0x26)          # 封筒の折り返し線（バーの背景色）


def hex_rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def rounded_rect(x, y, x0, y0, x1, y1, r):
    if not (x0 <= x <= x1 and y0 <= y <= y1):
        return False
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def near_segment(x, y, ax, ay, bx, by, half):
    dx, dy = bx - ax, by - ay
    t = 0.0 if dx == dy == 0 else ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)
    t = min(1.0, max(0.0, t))
    px, py = ax + t * dx, ay + t * dy
    return (x - px) ** 2 + (y - py) ** 2 <= half * half


def render(color):
    # 3x3 のスーパーサンプリングで縁を滑らかにする（トレイでは縮小表示される）
    body = (6, 18, 58, 48, 6)          # x0, y0, x1, y1, 半径
    flap = ((7, 19), (32, 37), (57, 19))
    rows = []
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            cov_body = cov_flap = 0
            for sy in range(3):
                for sx in range(3):
                    x = px + (sx + 0.5) / 3
                    y = py + (sy + 0.5) / 3
                    if rounded_rect(x, y, *body):
                        cov_body += 1
                        if (near_segment(x, y, *flap[0], *flap[1], 2.6)
                                or near_segment(x, y, *flap[1], *flap[2], 2.6)):
                            cov_flap += 1
            if cov_body == 0:
                row += b"\x00\x00\x00\x00"
                continue
            a = round(255 * cov_body / 9)
            f = cov_flap / cov_body                      # 折り返し線の混ざり具合
            rgb = tuple(round(c * (1 - f) + b * f) for c, b in zip(color, BG))
            row += bytes((*rgb, a))
        rows.append(bytes(row))
    return rows


def png(rows):
    raw = b"".join(b"\x00" + r for r in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


if __name__ == "__main__":
    color, out = hex_rgb(sys.argv[1]), sys.argv[2]
    with open(out, "wb") as fh:
        fh.write(png(render(color)))
PY

python3 "$tmp/gen.py" "$ICON_READ_COLOR"   "$tmp/read.png"
python3 "$tmp/gen.py" "$ICON_UNREAD_COLOR" "$tmp/unread.png"

# Birdtray はアイコンを base64 の PNG 文字列として設定に埋め込みます
read_b64=$(base64 -w0 < "$tmp/read.png")
unread_b64=$(base64 -w0 < "$tmp/unread.png")

# --- 設定に差し込む（他のキーは触らない）
jq --arg read "$read_b64" --arg unread "$unread_b64" '
  .["common/notificationicon"]       = $read
  | .["common/notificationiconunread"] = $unread
  | .["common/showunreademailcount"]   = false
  | .["advanced/unreadopacitylevel"]   = 1.0
  | .["common/showhidethunderbird"]    = true
' "$CONFIG" > "$tmp/patched.json"

# 何度実行しても .bak が増えないよう、変わらないときは書き換えません
if cmp -s "$tmp/patched.json" "$CONFIG"; then
  echo "変更なし: $CONFIG"
else
  bak="$CONFIG.bak.$(date +%Y%m%d-%H%M%S)"
  cp -a "$CONFIG" "$bak"
  cp "$tmp/patched.json" "$CONFIG"
  echo "設定しました: $CONFIG"
  echo "  未読なし: $ICON_READ_COLOR / 未読あり: $ICON_UNREAD_COLOR（数字は出しません）"
  echo "  元の設定: $bak"
fi

if [[ $BIRDTRAY_WAS_RUNNING == true ]]; then
  birdtray >/dev/null 2>&1 &
  echo "birdtray を再起動しました。"
else
  echo "birdtray を起動すると反映されます。"
fi
