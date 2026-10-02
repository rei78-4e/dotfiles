#!/usr/bin/env bash
set -euo pipefail

tsc_bin="$(command -v tsc)"
ts_root="$(dirname "$(dirname "$(readlink -f "$tsc_bin")")")"
typescript_dir="$ts_root/lib/node_modules/typescript"
if [[ ! -d "$typescript_dir" ]]; then
  echo "astro-ls: TypeScript module not found next to $tsc_bin" >&2
  exit 1
fi

tsdk_link="${XDG_CACHE_HOME:-$HOME/.cache}/helix/astro-typescript"
mkdir -p "$(dirname "$tsdk_link")"
ln -sfnT "$typescript_dir" "$tsdk_link"
export NODE_PATH="$ts_root/lib/node_modules${NODE_PATH:+:$NODE_PATH}"
exec astro-ls "$@"
