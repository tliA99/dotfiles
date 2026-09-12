# ThinkPad X1 Carbon Gen 7 — EndeavourOS + Hyprland

EndeavourOS を入れた X1 Carbon Gen 7 を、Hyprland のデスクトップに仕立てるための設定一式です。

| ファイル | 用途 |
| --- | --- |
| `setup.sh` | パッケージ導入・電源まわり・設定配置をまとめて行うスクリプト |
| `config/hypr/hyprland.lua` | Hyprland 本体（**Lua 形式 / 0.55 以降**） |
| `config/hypr/hypridle.conf` | アイドル管理（画面暗転・ロック・サスペンド） |
| `config/hypr/hyprlock.conf` | ロック画面 |
| `config/hypr/hyprpaper.conf` | 壁紙 |
| `config/waybar/` | ステータスバー（設定 + CSS） |
| `config/wofi/` | ランチャ（設定 + CSS） |
| `config/foot/` | ターミナル |
| `config/swaync/` | 通知センター（設定 + CSS） |
| `config/greetd/` | ログイン画面（greetd + ReGreet の設定 + CSS） |

配色は Tokyo Night Storm で全部揃えてあります。

---

## いちばん重要な前提: Hyprland の設定言語が変わっています

うまく動かない原因のほとんどはこれです。

| バージョン | 何が変わったか |
| --- | --- |
| 0.51 | `gestures { workspace_swipe = true }` が**廃止**。`hl.gesture(...)` / `gesture = ...` に |
| 0.53 | ウィンドウルールの書式を**全面刷新**。`windowrulev2 = float, class:^(x)$` は通らない |
| 0.53 | 起動コマンドが `start-hyprland` に。`Hyprland` を直接叩くと警告が出る |
| 0.55 | **設定言語が hyprlang (`hyprland.conf`) から Lua (`hyprland.lua`) へ** |
| 0.56.1 | `.conf` を読み込むと非推奨の警告が出るように |

`.conf` は互換のためまだ読まれますが、**0.4x 世代の文法で書かれた `.conf` は 0.51 / 0.53 の破壊的変更に引っかかって設定エラーを連発します**。
このリポジトリはそれを踏まえて、全面的に **Lua 形式** に書き直してあります。

自分のバージョンの確認:

```bash
hyprctl version
```

`0.55` 未満だった場合は `sudo pacman -Syu` で上げてください（EndeavourOS はローリングなので上がります）。
`setup.sh` も導入時にバージョンを見て、古ければ警告します。

> `~/.config/hypr/` に `hyprland.lua` と `hyprland.conf` の両方があると `.lua` が優先されます。
> 混乱の元なので、`setup.sh` は古い `.conf` を `.conf.old` に退避します。

---

## 0. BIOS 設定

F1 で BIOS に入り、以下を確認します。

- `Config` → `Power` → `Sleep State` → **Linux**
  S3 スリープが使えるようになります。Gen 7 の大きな利点で、ここが `Windows` のままだと
  S0ix になり、蓋を閉じてもバッテリーが目に見えて減ります。
- `Security` → `Secure Boot` → **Disabled**（Secure Boot を組む予定がなければ）

---

## 1. セットアップ

EndeavourOS のインストールが済んで、ネットワークに繋がった状態から始めます。
デスクトップ環境は無し（No Desktop）でも、既に何か入っていても構いません。

```bash
git clone <このリポジトリ> ~/dotfiles
cd ~/dotfiles
chmod +x setup.sh
./setup.sh
```

設定を直したあとの再適用は、パッケージ導入を飛ばせます。
`/etc/greetd/` 以下を更新するときだけ sudo を聞かれます。

```bash
./setup.sh --configs-only          # config/ 以下を配置し直すだけ
./setup.sh --configs-only --link   # コピーではなくリポジトリへのシンボリックリンク
```

`--link` にしておくと、リポジトリを直接編集した内容がそのまま反映されるので、
詰めていく段階ではこちらが楽です。

スクリプトがやること:

1. pacman の設定調整とミラーの日本優先化（EndeavourOS 独自リポジトリのミラーも含む）
2. 基本ツール、PipeWire、NetworkManager、Bluetooth
3. Intel UHD 620 向けグラフィックスタック（VA-API は `iHD`）
4. TLP による電源管理（`power-profiles-daemon` があれば外す）と zram
5. Hyprland 一式、フォント、fcitx5 + Mozc
6. ログインマネージャ（greetd + ReGreet）の導入と有効化
7. 壁紙の生成と、`config/` 以下の設定配置

途中でパッケージが 1 つ見つからなくても止まりません。入らなかったものは最後にまとめて表示します。

---

## 2. ログイン画面と起動

ログインマネージャは **greetd + [ReGreet](https://github.com/rharish101/ReGreet)** です。
どちらも Arch の `extra` にあるので AUR は要りません。GTK4 製で Wayland ネイティブ、
CSS で自由に見た目を作れるので、Tokyo Night のまま他の設定と揃えてあります。

`setup.sh` が `greetd.service` を有効化するので、**再起動すればログイン画面が出ます**。
セッションの一覧で `Hyprland` を選べば、そのまま Hyprland が起動します
（一度選べば次回から既定になります）。ここが「Hyprland の自動起動」にあたります。

| ファイル | 置き場所 | 役割 |
| --- | --- | --- |
| `config/greetd/config.toml` | `/etc/greetd/config.toml` | greetd 本体。cage の中で ReGreet を動かす |
| `config/greetd/regreet.toml` | `/etc/greetd/regreet.toml` | 壁紙・時計・フォントなど |
| `config/greetd/regreet.css` | `/etc/greetd/regreet.css` | 配色（Tokyo Night Storm） |

greeter のコンポジタには **cage** を使っています。Hyprland 自体を使うこともできて
ReGreet の README にも例がありますが、Hyprland の更新で起動しなくなるとグラフィカル
ログインごと巻き添えになります。見た目は ReGreet 側で作り込んでいてコンポジタの差は
出ないので、壊れにくい cage にしてあります。

Hyprland を greeter にしたい場合は `/etc/greetd/config.toml` の `command` を
`dbus-run-session start-hyprland -- -c /etc/greetd/hyprland.lua` に変え、その Lua で
`hl.on("hyprland.start", ...)` から `regreet` を起動してください。

### 自動ログインにしたい場合

既定ではパスワードを求めます。持ち出すノートなので、盗難時にディスクの中身が
そのまま見えてしまう状態は避ける想定です。

不要なら `/etc/greetd/config.toml` に次を足してください。ログイン画面を経由せず
そのまま Hyprland が立ち上がります（`YOUR_USER` は自分のユーザー名に）。

```toml
[initial_session]
command = "start-hyprland"
user = "YOUR_USER"
```

なお自動ログインにしても、hypridle → hyprlock による**復帰時のロックは効いたまま**です。

### ログイン画面を使わない場合

`sudo systemctl disable --now greetd` で止めて、TTY から直接起動できます。

```bash
start-hyprland
```

TTY ログイン時に自動で起動させたいなら `~/.bash_profile`（zsh なら `~/.zprofile`）に:

```bash
[[ -z $WAYLAND_DISPLAY && $XDG_VTNR -eq 1 ]] && exec start-hyprland
```

### ログイン画面が出なくなったら

`Ctrl+Alt+F2` で TTY に切り替えられます。ログインして:

```bash
sudo systemctl disable --now greetd
journalctl -b -u greetd          # 原因はここに出ます
```

---

## 3. キーバインド

`SUPER` が修飾キーです。

| キー | 動作 |
| --- | --- |
| `SUPER + Return` | ターミナル (foot) |
| `SUPER + D` | ランチャ (wofi) |
| `SUPER + E` | ファイラ (thunar) |
| `SUPER + B` | ブラウザ (firefox) |
| `SUPER + C` | クリップボード履歴 |
| `SUPER + Q` | ウィンドウを閉じる |
| `SUPER + V` | フローティング切り替え |
| `SUPER + F` / `SUPER + SHIFT + F` | 全画面 / 最大化 |
| `SUPER + T` | ウィンドウを中央へ |
| `SUPER + H/J/K/L` | フォーカス移動（矢印キーも可） |
| `SUPER + SHIFT + H/J/K/L` | ウィンドウ移動 |
| `SUPER + CTRL + H/J/K/L` | リサイズ |
| `SUPER + 1〜0` | ワークスペース切り替え |
| `SUPER + SHIFT + 1〜0` | ワークスペースへ送る |
| `SUPER + S` | スクラッチパッド |
| `SUPER + ALT + J` | 分割方向の切り替え |
| `SUPER + ALT + L` | 画面ロック |
| `SUPER + SHIFT + Q` | ログアウト |
| `Print` / `SHIFT + Print` / `SUPER + Print` | 範囲選択→クリップボード / 全画面→クリップボード / 範囲選択→保存 |

> ロックと分割切り替えを `ALT` 側に逃がしているのは、`SUPER + L` / `SUPER + J` が
> `h/j/k/l` のフォーカス移動と衝突するためです。元の設定ではここが二重定義になっていて、
> フォーカス移動が効かない原因になっていました。

3 本指の横スワイプでワークスペースを切り替えられます。

---

## 4. 動かないときの調べ方

まずログを見ます。Hyprland は設定エラーを起動時にポップアップで出しますが、詳細はログにあります。

```bash
hyprctl reload                                  # 設定を読み直す（エラーがあればその場で出る）
tail -f $XDG_RUNTIME_DIR/hypr/*/hyprland.log
```

よくある症状と原因:

| 症状 | 見るところ |
| --- | --- |
| 起動直後に設定エラーのポップアップ | 0.4x 世代の `.conf` が残っていないか（`~/.config/hypr/hyprland.conf`） |
| ロックのキーを押しても何も起きない | `hyprlock.conf` が無い。hyprlock は設定が無いと**エラー終了**します |
| 一定時間で暗くならない / スリープしない | `hypridle.conf` が無い。hypridle も設定が無いと起動しません |
| 壁紙が出ない | `~/Pictures/wallpapers/wall.png` が無い |
| 認証ダイアログが出ない | `hyprpolkitagent` は PATH に無く `/usr/lib/` 以下にあります。`systemctl --user start hyprpolkitagent` で起動します |
| バーが出ない | `~/.config/waybar/config.jsonc` の JSON が壊れている。`waybar` を端末から直接起動するとエラーが見えます |
| バーは出るがワークスペースが空 | モジュール名が `sway/workspaces` になっていないか（`hyprland/workspaces` が正解） |
| アイコンが豆腐 | Nerd Font（`ttf-jetbrains-mono-nerd`）が入っているか |
| 日本語が豆腐 | `noto-fonts-cjk` が入っているか |
| foot が `invalid section name colors` | foot 1.26 で `[colors]` は廃止。`[colors-dark]` / `[colors-light]` に分かれました |
| ログイン画面が真っ黒 / 出ない | `journalctl -b -u greetd`。`Ctrl+Alt+F2` で TTY に逃げられます |
| ログイン画面の壁紙が出ない | `/usr/share/backgrounds/hypr/wall.png` が無い。greeter は `$HOME` を読めません |
| 全体が大きすぎる / 小さすぎる | `hyprctl monitors` の `scale:`。`hyprland.lua` の `monitor_scale` で調整 |
| XWayland アプリだけぼやける | スケールが端数（1.25 / 1.5）になっている。整数倍率にすると直ります |
| 日本語入力が出ない | `fcitx5 -d` が起動しているか。XWayland アプリは `XMODIFIERS=@im=fcitx` が必要 |

デバイス名（トラックポイントや Lid Switch）が合っているかは:

```bash
hyprctl devices
hyprctl monitors
hyprctl layers      # レイヤールールの namespace 確認用
```

---

## 5. カスタマイズの勘どころ

### バッテリーと見た目のトレードオフ

`hyprland.lua` の `decoration.blur` が一番効きます。UHD 620 は blur を有効にすると GPU が回り続けます。

```lua
blur = {
    enabled = true,   -- 持ち時間を優先するなら false
    passes  = 1,      -- 上げるほど重い。2 以上は Gen 7 には勧めません
    xray    = true,   -- 下のタイル済みウィンドウを計算から外す。見た目ほぼ据え置きで軽くなる
}
```

`animations.borderangle` の `loop` スタイルは、画面に何も映っていなくても
リフレッシュレート分だけ再描画が走るので使っていません。

### 解像度・スケール（表示が大きすぎる / 小さすぎるとき）

`hyprland.lua` の先頭近くにある `monitor_scale` を変えてください。

Hyprland の `scale = "auto"` は**使っていません**。auto は対角 PPI だけで決め打ちしていて
（`src/output/Monitor.cpp` の `getDefaultScale()`。140 超で 1.5 倍、200 超で 2 倍）、
14 インチの 1920x1080 は 158 PPI なので 1.5 倍が選ばれてしまいます。
論理解像度が 1280x720 相当になり、何もかも大きく表示されます。

| パネル | 対角PPI | `auto` の結果 | おすすめ | 適用後の論理解像度 |
| --- | --- | --- | --- | --- |
| 1920x1080 | 158 | 1.5 | **1** | 1920x1080 |
| 2560x1440 | 210 | 2 | **1.25** | 2048x1152 |
| 3840x2160 | 315 | 2 | **2** | 1920x1080 |

現在の倍率の確認と、再起動せずに試す方法:

```bash
hyprctl monitors                                          # scale: の行を見る
hyprctl eval 'hl.monitor({ output = "eDP-1", scale = 1 })'  # その場で適用
```

`hyprctl eval` での変更は再読み込みで元に戻るので、気に入った値を
`monitor_scale` に書いてから `hyprctl reload` してください。

端数倍率（1.25 / 1.5）は、XWayland 経由のアプリが一度拡大されてぼやけます。
整数倍率で収まるならそちらが無難です。

### スケールを変えずに文字だけ大きく / 小さくしたい

倍率を触るとレイアウト全体が動くので、文字サイズだけ調整したい場合はこちらです。

| 対象 | 場所 | 項目 |
| --- | --- | --- |
| ターミナル | `config/foot/foot.ini` | `font=...:size=10.5` |
| ステータスバー | `config/waybar/style.css` | `* { font-size: 13px }` と `config.jsonc` の `height` |
| ランチャ | `config/wofi/style.css` | `* { font-size: 14px }` |
| 通知 | `config/swaync/style.css` | `* { font-size: 13px }` |
| ロック画面 | `config/hypr/hyprlock.conf` | 各ウィジェットの `font_size` |
| GTK アプリ全般 | `nwg-look` か `gsettings` | `org.gnome.desktop.interface font-name` |
| カーソル | `config/hypr/hyprland.lua` | `hl.env("XCURSOR_SIZE", "24")` |

タイル間の余白や角丸を詰めたい場合は `hyprland.lua` の `general.gaps_in` /
`gaps_out` と `decoration.rounding` です。

### カーネルパラメータ

EndeavourOS は dracut + systemd-boot が既定です。パラメータを足すなら:

```bash
sudo nvim /etc/kernel/cmdline    # 1 行のファイル
sudo reinstall-kernels           # initrd の再生成とブートエントリの更新
```

GRUB を選んで入れた場合は `/etc/default/grub` の `GRUB_CMDLINE_LINUX_DEFAULT` を編集して
`sudo grub-mkconfig -o /boot/grub/grub.cfg` です。

なお、かつて X1 Carbon 向けによく足されていた `i915.enable_psr=1` `i915.enable_fbc=1` は、
最近のカーネルでは既定で有効なので不要です。画面がちらつく場合に `i915.enable_psr=0` で
**切る**方向で使ってください。

---

## 6. 導入後にやること

### バッテリーの状態確認

```bash
upower -i /org/freedesktop/UPower/devices/battery_BAT0
```

`energy-full` を見ます。Gen 7 の設計容量は 51Wh。

- **45Wh 以上** — 劣化は軽微。電源管理側（PSR、C-state、常駐プロセス）を疑う
- **35〜45Wh** — 相応に劣化。交換の検討価値あり
- **35Wh 未満** — 交換推奨。純正型番 `02DL004`

充電しきい値は `setup.sh` が 60/80 に設定します。持ち出しが多いなら
`/etc/tlp.d/01-x1c7.conf` で 75/95 に上げてください。

```bash
cat /sys/class/power_supply/BAT0/charge_control_{start,end}_threshold
```

### C-state の確認

```bash
sudo powertop
```

Idle Stats タブで C8 / C9 / C10 に時間が入っていれば正常です。C3 止まりなら何かが CPU を起こし続けています。

### ファームウェア更新

```bash
fwupdmgr refresh && fwupdmgr get-updates && fwupdmgr update
```

ThinkPad は BIOS も ME も LVFS 経由で流れてきます。

---

## 7. さらに作り込むなら

`hyprland.lua` は Lua なので、`require()` でファイルを分割できます。
分割したファイルは独立したスコープで読まれるため、片方でエラーが出ても
もう片方は生き残ります。設定が育ってきたら早めに分けるのがおすすめです。

```lua
require("keybinds")     -- ~/.config/hypr/keybinds.lua
require("./rules/*")    -- ~/.config/hypr/rules/ 以下すべて
```

参考になるリポジトリ（Hyprland 公式 wiki が挙げているもの）:

- [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) — Material 系。完成度が高い
- [HyDE-Project/HyDE](https://github.com/HyDE-Project/HyDE) — ミニマル寄り。ターミナル中心の人向け
- [mylinuxforwork/dotfiles](https://github.com/mylinuxforwork/dotfiles) (ML4W) — インストーラ込みで構成を俯瞰しやすい
- [JaKooLit/Hyprland-Dots](https://github.com/JaKooLit/Hyprland-Dots) — ディストロ別のインストールスクリプト付き
- [Omarchy](https://omarchy.org/) — Arch + Hyprland の意見の強い既製セット

丸ごと入れるのではなく、気に入った箇所だけ移植する進め方を推奨します。
これらは**システムに深く手を入れるものが多く、後から剥がすのが想像以上に大変です**
（公式 wiki も同じ警告をしています）。

いま参照している設定が自分のバージョン向けか確認するときは、
[Hyprland Wiki](https://wiki.hypr.land/) 右上のバージョンセレクタを合わせてください。
既定は git 版のドキュメントです。
