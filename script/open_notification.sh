#!/usr/bin/env bash

set -euo pipefail

if systemctl --user is-active noctalia.service; then
  noctalia msg panel-toggle control-center
else
  swaync-client -t
fi
