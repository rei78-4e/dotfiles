#!/usr/bin/env bash

set -euo pipefail

if systemctl --user is-active noctalia.service; then
  noctalia msg panel-toggle wallpaper
else
  dir="$HOME/Pictures/wallpapers"

  awww img $(fd \
    --absolute-path \
    --type f \
    --extension jpg \
    --extension jpeg \
    --extension png \
    --extension webp \
    --extension avif \
    . "$dir" |
    vicinae dmenu \
      --width 1000 \
      --height 650 \
      --placeholder "Select wallpaper")
fi
