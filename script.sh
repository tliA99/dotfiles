#!/usr/bin/env bash

export LANG=C

sudo pacman -S --needed hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  hypridle hyprlock hyprpaper hyprpolkitagent \
  waybar wofi swaync foot \
  grim slurp wl-clipboard cliphist \
  brightnessctl playerctl pamixer \
  qt5-wayland qt6-wayland \
  noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-jetbrains-mono-nerd \
  fcitx5-im fcitx5-mozc \
  pipewire pipewire-alsa pipewire-pulse wireplumber \
  mesa vulkan-intel intel-media-driver

mkdir -p ~/.config/hypr
cp ~/dotfiles/hyprland.conf ~/.config/hypr/
