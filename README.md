# ThinkPad X1 Carbon Gen 7 — Arch + Hyprland セットアップ

## 構成

| ファイル | 用途 |
| --- | --- |
| `README.md` | 手動で行う部分の手順書（このファイル） |
| `setup.sh` | 初回起動後に実行する環境構築スクリプト |
| `hyprland.conf` | 最小構成の Hyprland 設定（叩き台） |

パーティショニングと `pacstrap` はスクリプト化していません。ディスクを消す操作を自動化する利点がないためです。

---

## 0. BIOS 設定（インストール前）

F1 で BIOS に入り、以下を変更します。

- `Security` → `Secure Boot` → **Disabled**
- `Config` → `Power` → `Sleep State` → **Linux**（S3 が使えるようになる。Gen 7 の利点）
- `Config` → `Thunderbolt BIOS Assist Mode` → Disabled のままでよい
- `Startup` → `UEFI/Legacy Boot` → **UEFI Only**

保存して F10。

---

## 1. USB から起動

F12 連打 → USB HDD を選択。

キーボードとフォントを日本語環境向けに整えます（任意）。

```bash
loadkeys jp106          # JIS 配列なら
setfont ter-132b        # HiDPI で文字が小さい場合
```

Wi-Fi 接続:

```bash
iwctl
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
[iwd]# station wlan0 connect <SSID>
[iwd]# exit

ping -c3 archlinux.jp
```

時刻同期:

```bash
timedatectl set-ntp true
```

---

## 2. パーティショニング

まずデバイス名を確認します。Gen 7 は NVMe なので `/dev/nvme0n1` のはずです。

```bash
lsblk
```

**既存の Windows を残さない前提**で進めます。残す場合はこの節を読み替えてください。

```bash
gdisk /dev/nvme0n1
```

| 番号 | サイズ | タイプコード | 用途 |
| --- | --- | --- | --- |
| 1 | 1G | `ef00` | EFI システムパーティション |
| 2 | 残り全部 | `8300` | ルート |

swap パーティションは切らず、後述の zram で済ませます。ハイバネートを使いたい場合のみ、メモリ容量ぶんの swap を切ってください。

フォーマット:

```bash
mkfs.fat -F32 /dev/nvme0n1p1
mkfs.ext4 /dev/nvme0n1p2
```

btrfs を使いたい場合はここを差し替えてください。スナップショットが要らないなら ext4 で十分です。

マウント:

```bash
mount /dev/nvme0n1p2 /mnt
mount --mkdir /dev/nvme0n1p1 /mnt/boot
```

---

## 3. ベースシステム

日本のミラーを優先させます。

```bash
reflector --country Japan --age 12 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
```

```bash
pacstrap -K /mnt base linux linux-firmware linux-headers \
  intel-ucode sof-firmware \
  networkmanager \
  vim sudo man-db man-pages
```

`sof-firmware` は Gen 7 のオーディオに必須です。ここで入れ忘れると初回起動後に無音になります。

```bash
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt
```

---

## 4. chroot 内の設定

```bash
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc
```

ロケール。`/etc/locale.gen` の以下2行をコメント解除:

```
en_US.UTF-8 UTF-8
ja_JP.UTF-8 UTF-8
```

```bash
locale-gen
echo 'LANG=ja_JP.UTF-8' > /etc/locale.conf
echo 'KEYMAP=jp106' > /etc/vconsole.conf     # JIS 配列の場合
echo 'x1c7' > /etc/hostname
```

`/etc/hosts`:

```
127.0.0.1   localhost
::1         localhost
127.0.1.1   x1c7.localdomain x1c7
```

ユーザー作成:

```bash
passwd                                  # root のパスワード
useradd -m -G wheel -s /bin/bash sota
passwd sota
EDITOR=vim visudo                       # %wheel ALL=(ALL:ALL) ALL を有効化
```

---

## 5. ブートローダ（systemd-boot）

```bash
bootctl install
```

`/boot/loader/loader.conf`:

```
default arch.conf
timeout 3
console-mode max
editor no
```

ルートパーティションの UUID を取得:

```bash
blkid -s UUID -o value /dev/nvme0n1p2
```

`/boot/loader/entries/arch.conf`（UUID は上で出た値に置き換え）:

```
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx rw i915.enable_psr=1 i915.enable_fbc=1 i915.enable_guc=2 nowatchdog
```

`i915.enable_psr=1` は画面がちらつくようなら `0` に戻してください。Gen9 世代では過去に報告がありましたが、最近のカーネルではほぼ解消しています。

```bash
systemctl enable NetworkManager
exit
umount -R /mnt
reboot
```

USB を抜くのを忘れずに。

---

## 6. 初回起動後

有線か `nmcli` で Wi-Fi に繋いでから、スクリプトを実行します。

```bash
nmcli device wifi connect <SSID> password <PASSWORD>

git clone <このディレクトリ> ~/setup   # あるいは USB でコピー
cd ~/setup
chmod +x setup.sh
./setup.sh
```

スクリプトは対話的に確認を挟みます。root では実行しないでください。

---

## 7. スクリプト実行後にやること

### バッテリーの状態確認

```bash
upower -i /org/freedesktop/UPower/devices/battery_BAT0
```

`energy-full` を見ます。Gen 7 の設計容量は 51Wh。

- **45Wh 以上** — 劣化は軽微。電源管理側（PSR、C-state、常駐プロセス）を疑う
- **35〜45Wh** — 相応に劣化。交換の検討価値あり
- **35Wh 未満** — 交換推奨。純正型番 `02DL004`

C-state が深く落ちているかの確認:

```bash
sudo powertop
```

Idle Stats タブで C8 / C9 / C10 に時間が入っていれば正常です。C3 止まりなら何かが CPU を起こし続けています。

### ファームウェア更新

```bash
fwupdmgr refresh
fwupdmgr get-updates
fwupdmgr update
```

ThinkPad は BIOS も ME も LVFS 経由で流れてきます。Linux から更新できるので活用してください。

### Hyprland の起動

```bash
Hyprland
```

TTY から直接叩きます。ログインマネージャは入れていません。自動起動させたい場合は `~/.bash_profile` に:

```bash
[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec Hyprland
```

---

## 8. その後の作り込み

`hyprland.conf` は動く最小構成です。ここから読むと参考になるリポジトリ:

- `end-4/dots-hyprland` — 完成度が高い。animations ブロックと waybar の CSS が特に参考になる
- `caelestia-dots/shell` — 更新が活発。アニメーション寄り
- `mylinuxforwork/dotfiles` — インストーラ込みで構成を俯瞰しやすい

丸ごと入れるのではなく、気に入った箇所だけ移植する進め方を推奨します。UHD 620 で blur を重ねるとバッテリーに効きます。

### Niri を試す場合

```bash
sudo pacman -S niri xwayland-satellite
```

TTY から `niri` で起動。waybar と foot はそのまま流用できます。合わなければ消すだけです。
