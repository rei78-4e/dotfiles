#!/usr/bin/env bash
set -uo pipefail

profile=$(tlp-stat -s 2>/dev/null | awk -F ' = ' '
  tolower($1) ~ /^(tlp profile|power profile)[[:space:]]*$/ { print $2; exit }
')

jq -nc --arg tooltip "TLP: ${profile:-unavailable}" \
  '{text: "󰌪", tooltip: $tooltip}'
