--
-- Hyprland — ThinkPad X1 Carbon Gen 7 (Whiskey Lake / UHD 620)
--
-- Hyprland 0.55 以降の Lua 設定です。0.54 以前の hyprland.conf (hyprlang) とは
-- 別物なので、古い設定は読み込ませないでください（両方あると .lua が優先されます）。
--
--   設定リファレンス: https://wiki.hypr.land/configuring/core/
--   エディタ補完:     /usr/share/hypr/stubs/ を LSP の library に追加
--
-- 配色は Tokyo Night Storm で waybar / wofi / foot / hyprlock と揃えてあります。
--

------------------------------------------------------------------ パレット

local c = {
    bg        = "1a1b26",
    bg_alt    = "24283b",
    surface   = "292e42",
    fg        = "c0caf5",
    muted     = "565f89",
    blue      = "7aa2f7",
    cyan      = "7dcfff",
    green     = "9ece6a",
    yellow    = "e0af68",
    red       = "f7768e",
    magenta   = "bb9af7",
}

------------------------------------------------------------------ 使うアプリ

local terminal     = "foot"
local fileManager  = "thunar"
local browser      = "firefox"
local menu         = "wofi --show drun"
local clipboard    = "cliphist list | wofi --dmenu | cliphist decode | wl-copy"

------------------------------------------------------------------ モニタ

-- scale = "auto" にしておくと PPI から倍率を決めるので、
-- 1920x1080 モデルでも 2560x1440 / 3840x2160 モデルでもそのまま動きます。
-- 気に入らなければ scale = 1 や 2 に固定してください（`hyprctl monitors` で確認）。
hl.monitor({
    output   = "eDP-1",
    mode     = "preferred",
    position = "0x0",
    scale    = "auto",
})

-- 外部モニタは自動で右に並べる（マッチしなかった全モニタのフォールバック）
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

------------------------------------------------------------------ 環境変数

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")     -- setup.sh が qt6ct を入れます
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- Gen9 世代の Intel GPU は iHD (intel-media-driver) を使う
hl.env("LIBVA_DRIVER_NAME", "iHD")

-- fcitx5: Wayland ネイティブなアプリは text-input-v3 を使うので GTK_IM_MODULE は
-- 設定しません（設定すると GTK4 アプリで二重入力になることがある）。
-- XMODIFIERS は XWayland 経由のアプリのために必要です。
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("QT_IM_MODULE", "fcitx")

------------------------------------------------------------------ 自動起動

hl.on("hyprland.start", function()
    -- 認証エージェント。バイナリは PATH に無く /usr/lib 以下にあるので、
    -- 直接叩かず必ず systemd ユーザーユニット経由で起動します。
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")

    hl.exec_cmd("waybar")
    hl.exec_cmd("swaync")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("fcitx5 -d")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")

    -- 壁紙。hyprpaper は設定内の path が実在しないと何も出ないので、
    -- setup.sh が ~/Pictures/wallpapers/wall.png を用意してから起動します。
    hl.exec_cmd("hyprpaper")
end)

------------------------------------------------------------------ 見た目

hl.config({
    general = {
        gaps_in  = 4,
        gaps_out = 8,
        border_size = 2,

        col = {
            active_border   = { colors = { "rgba(" .. c.blue .. "ee)", "rgba(" .. c.magenta .. "ee)" }, angle = 45 },
            inactive_border = "rgba(" .. c.surface .. "aa)",
        },

        layout           = "dwindle",
        resize_on_border = true,
        allow_tearing    = false,

        snap = { enabled = true },
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2.4,

        active_opacity   = 1.0,
        inactive_opacity = 0.94,

        dim_inactive = true,
        dim_strength = 0.08,

        -- --- ここがバッテリーに一番効く箇所 -------------------------------
        -- UHD 620 では blur が常時 GPU を回します。passes を上げるほど重い。
        -- バッテリー優先にしたいときは enabled = false にしてください。
        -- xray = true は、下のタイル済みウィンドウを blur 計算から外すので
        -- 見た目をほぼ落とさずに負荷がかなり下がります。
        blur = {
            enabled           = true,
            size              = 4,
            passes            = 1,
            new_optimizations = true,
            xray              = true,
            vibrancy          = 0.15,
            noise             = 0.008,
            popups            = true,
            input_methods     = false,  -- fcitx5 の候補窓は blur しない
        },

        shadow = {
            enabled      = true,
            range        = 14,
            render_power = 3,
            color        = "rgba(0d0e14cc)",
        },
    },

    animations = { enabled = true },

    -- pseudotile というグローバル設定は廃止されました。
    -- pseudo はウィンドウ単位の操作になり、SUPER + P のバインドがそれです。
    dwindle = {
        preserve_split = true,
    },

    misc = {
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        background_color        = "rgb(" .. c.bg .. ")",
        vrr                     = 0,   -- eDP は VRR 非対応。1 にすると悪化することがある
        focus_on_activate       = true,
        enable_swallow          = false,
        font_family             = "Noto Sans CJK JP",
    },

    cursor = {
        inactive_timeout = 4,
        hide_on_key_press = true,
    },

    render = {
        -- 非力な iGPU では有効にすると体感が滑らかになります
        new_render_scheduling = true,
    },
})

------------------------------------------------------------------ アニメーション

hl.curve("smooth", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })
hl.curve("snappy", { type = "bezier", points = { { 0.2, 1.0 }, { 0.3, 1.0 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
-- 減衰のキーは dampening。damping は新しい版で足された別名なので、
-- 古い版でも通る dampening を使います。
hl.curve("bounce", { type = "spring", mass = 1, stiffness = 250, dampening = 22 })

hl.animation({ leaf = "windowsIn",   enabled = true, speed = 4.0, spring = "bounce", style = "popin 85%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 2.5, bezier = "smooth", style = "popin 85%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4.0, bezier = "snappy" })
hl.animation({ leaf = "border",      enabled = true, speed = 6.0, bezier = "linear" })
hl.animation({ leaf = "fade",        enabled = true, speed = 3.0, bezier = "smooth" })
hl.animation({ leaf = "layersIn",    enabled = true, speed = 3.0, bezier = "snappy", style = "fade" })
hl.animation({ leaf = "layersOut",   enabled = true, speed = 2.0, bezier = "linear", style = "fade" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 4.0, bezier = "snappy", style = "slidefade" })

-- borderangle の loop は毎フレーム再描画が走りバッテリーを食うので使いません。

------------------------------------------------------------------ 入力

hl.config({
    input = {
        kb_layout  = "jp",   -- US 配列なら "us"
        kb_options = "",

        follow_mouse = 1,
        sensitivity  = 0,

        repeat_delay = 250,
        repeat_rate  = 40,

        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
            scroll_factor        = 0.5,
            clickfinger_behavior = true,
            -- タップ操作は既定で有効なので指定していません。無効にしたい場合は
            -- キー名がハイフン区切りなので Lua では角括弧で書く必要があります:
            --   ["tap-to-click"] = false,
            --   ["tap-and-drag"] = false,
        },
    },
})

-- トラックポイント。感度が合わなければ調整する（名前は `hyprctl devices` で確認）
hl.device({
    name        = "tpps/2-elan-trackpoint",
    sensitivity = 0.2,
})

-- 3 本指スワイプでワークスペース切り替え
-- （0.51 で gestures:workspace_swipe は廃止され、この形式になりました）
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 4, direction = "up",   mods = "SUPER", action = "fullscreen" })

------------------------------------------------------------------ キーバインド

local mod = "SUPER"

-- --- アプリ起動
hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal),    { description = "ターミナル" })
hl.bind(mod .. " + D",      hl.dsp.exec_cmd(menu),        { description = "ランチャ" })
hl.bind(mod .. " + E",      hl.dsp.exec_cmd(fileManager), { description = "ファイラ" })
hl.bind(mod .. " + B",      hl.dsp.exec_cmd(browser),     { description = "ブラウザ" })
hl.bind(mod .. " + C",      hl.dsp.exec_cmd(clipboard),   { description = "クリップボード履歴" })

-- --- ウィンドウ操作
hl.bind(mod .. " + Q",          hl.dsp.window.close())
hl.bind(mod .. " + V",          hl.dsp.window.float())
hl.bind(mod .. " + P",          hl.dsp.window.pseudo())
hl.bind(mod .. " + F",          hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mod .. " + SHIFT + F",  hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mod .. " + T",          hl.dsp.window.center())

-- togglesplit / ロックは h/j/k/l のフォーカス移動と衝突するので ALT 側に逃がしています。
-- （元の設定では SUPER+J と SUPER+L が二重に割り当てられていました）
hl.bind(mod .. " + ALT + J", hl.dsp.layout("togglesplit"))
hl.bind(mod .. " + ALT + L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"), { description = "画面ロック" })

hl.bind(mod .. " + SHIFT + Q", hl.dsp.exec_cmd(
    "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"),
    { description = "ログアウト" })

-- --- フォーカス移動（vim 風 + 矢印）
for key, dir in pairs({ H = "left", L = "right", K = "up", J = "down" }) do
    hl.bind(mod .. " + " .. key, hl.dsp.focus({ direction = dir }))
end
for key, dir in pairs({ left = "left", right = "right", up = "up", down = "down" }) do
    hl.bind(mod .. " + " .. key, hl.dsp.focus({ direction = dir }))
end

-- --- ウィンドウ移動
for key, dir in pairs({ H = "left", L = "right", K = "up", J = "down" }) do
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ direction = dir }))
end

-- --- リサイズ
hl.bind(mod .. " + CTRL + H", hl.dsp.window.resize({ x = -40, y = 0,   relative = true }), { repeating = true })
hl.bind(mod .. " + CTRL + L", hl.dsp.window.resize({ x = 40,  y = 0,   relative = true }), { repeating = true })
hl.bind(mod .. " + CTRL + K", hl.dsp.window.resize({ x = 0,   y = -40, relative = true }), { repeating = true })
hl.bind(mod .. " + CTRL + J", hl.dsp.window.resize({ x = 0,   y = 40,  relative = true }), { repeating = true })

-- --- ワークスペース
for i = 1, 10 do
    local key = i % 10   -- 10 は 0 キー
    hl.bind(mod .. " + " .. key,           hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key,   hl.dsp.window.move({ workspace = i }))
end

hl.bind(mod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- --- マウスドラッグ
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- --- スクリーンショット
hl.bind("Print",          hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
hl.bind("SHIFT + Print",  hl.dsp.exec_cmd("grim - | wl-copy"))
hl.bind(mod .. " + Print", hl.dsp.exec_cmd(
    'mkdir -p ~/Pictures/screenshots && grim -g "$(slurp)" ~/Pictures/screenshots/$(date +%Y%m%d-%H%M%S).png'))

-- --- ThinkPad のファンクションキー
--     locked = true でロック画面中も効きます。
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- ThinkPad の F4 は XF86AudioMicMute、F9〜F11 はディスプレイ/設定系。
-- 何が飛んでいるか分からないときは `wev` で確認してください。

------------------------------------------------------------------ 蓋の開閉

-- 解像度をベタ書きすると 4K モデルで壊れるので、disabled のトグルだけにしています。
-- サスペンドやロックは logind + hypridle 側の仕事です（hypridle.conf 参照）。
hl.bind("switch:on:Lid Switch",  function() hl.monitor({ output = "eDP-1", disabled = true  }) end, { locked = true })
hl.bind("switch:off:Lid Switch", function() hl.monitor({ output = "eDP-1", disabled = false }) end, { locked = true })

------------------------------------------------------------------ ウィンドウルール

-- 0.53 でルールの書式が総入れ替えになりました。windowrulev2 = ... は通りません。

hl.window_rule({
    name  = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- XWayland のドラッグ不具合対策（上流の例より）
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

hl.window_rule({
    name  = "float-utils",
    match = { class = "^(pavucontrol|org\\.pulseaudio\\.pavucontrol|blueman-manager|nm-connection-editor|nwg-look|qt6ct)$" },
    float  = true,
    center = true,
    size   = { 960, 640 },
})

hl.window_rule({
    name  = "float-dialogs",
    match = { title = "^(Open File|Save File|Open Folder|ファイルを開く|名前を付けて保存)$" },
    float  = true,
    center = true,
})

hl.window_rule({
    name  = "picture-in-picture",
    match = { title = "^(Picture-in-Picture|ピクチャーインピクチャー)$" },
    float = true,
    pin   = true,
    size  = { 640, 360 },
    move  = { "monitor_w-660", "monitor_h-400" },
})

-- ターミナルだけ少し透過させる（blur と相性がいい）
hl.window_rule({
    name    = "term-opacity",
    match   = { class = "^foot$" },
    opacity = "0.92 0.86",
})

-- 全画面のときは透過も角丸も切る
hl.window_rule({
    name  = "opaque-fullscreen",
    match = { fullscreen = true },
    opacity  = "1.0 override 1.0 override",
    rounding = 0,
    no_blur  = true,
})

------------------------------------------------------------------ レイヤールール

hl.layer_rule({ name = "blur-waybar", match = { namespace = "^waybar$" },  blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ name = "blur-wofi",   match = { namespace = "^wofi$" },    blur = true, ignore_alpha = 0.3 })
hl.layer_rule({ name = "blur-swaync", match = { namespace = "^swaync-.*" }, blur = true, ignore_alpha = 0.3 })
