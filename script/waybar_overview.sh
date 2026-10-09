#!/usr/bin/env bash
# ~/.config/niri/waybar-overview.sh
niri msg -j event-stream |
  jq --unbuffered -r 'select(.OverviewOpenedOrClosed) | .OverviewOpenedOrClosed.is_open' |
  while read -r _; do
    pkill -SIGUSR1 waybar
  done
