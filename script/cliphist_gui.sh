#!/usr/bin/env bash

set -euo pipefail

if systemctl --user is-active noctalia.service; then
  noctalia msg panel-toggle clipboard
else
  cliphist list | rofi -dmenu -p ' ' | cliphist decode | wl-copy

  # tmpdir="$(mktemp -d)"
  # trap 'rm -rf "$tmpdir"' EXIT

  # declare -a ids=()
  # declare -a entries=()

  # while IFS=$'\t' read -r id preview; do
  #   ids+=("$id")

  #   if [[ "$preview" =~ ^\[\[\ binary\ data.*\ (png|jpg|jpeg|webp|gif|bmp)\  ]]; then
  #     ext="${BASH_REMATCH[1]}"

  #     [[ "$ext" == "jpeg" ]] && ext="jpg"

  #     file="$tmpdir/$id.$ext"

  #     printf '%s' "$id" |
  #       cliphist decode >"$file"

  #     entries+=("$file")
  #   else
  #     entries+=("$preview")
  #   fi
  # done < <(cliphist list)

  # ((${#entries[@]} > 0)) || exit 0

  # selected_index="$(
  #   printf '%s\n' "${entries[@]}" |
  #     vicinae dmenu \
  #       --format index \
  #       --width 1000 \
  #       --height 600 \
  #       --placeholder "Clipboard history"
  # )" || exit 0

  # [[ -n "$selected_index" ]] || exit 0

  # printf '%s' "${ids[$selected_index]}" |
  #   cliphist decode |
  #   wl-copy
fi
