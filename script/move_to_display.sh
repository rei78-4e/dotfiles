#!/usr/bin/env bash

set -euo pipefail

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  output=$(
    hyprctl -j monitors |
      jq -r '.[].name' |
      rofi -dmenu -p "󰍺 "
  )

  [[ -z "$output" ]] && exit 0

  hyprctl dispatch "hl.dsp.window.move({ monitor = \"$output\", follow = false })"
  exit 0
fi

output=$(
  niri msg -j outputs |
    jq -r '.[].name' |
    rofi -dmenu -p "󰍺 "
)

[[ -z "$output" ]] && exit 0

niri msg action move-window-to-monitor "$output"
