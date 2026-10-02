#!/usr/bin/env bash
# Keep recent Nix generations and reclaim unreachable store paths.
#
# Run without arguments to preview changes.  `--apply` is required before any
# profile generations or store paths are removed.

set -euo pipefail

readonly RETENTION_GENERATIONS=10
readonly USER_STATE_DIR="${XDG_STATE_HOME:-"$HOME/.local/state"}/nix/profiles"
readonly USER_PROFILE="$USER_STATE_DIR/profile"
readonly HOME_MANAGER_PROFILE="$USER_STATE_DIR/home-manager"
readonly SYSTEM_PROFILE="/nix/var/nix/profiles/system"

usage() {
  cat <<'EOF'
Usage: nix-gc-cleanup.sh [--apply]

Preview keeping the latest 10 generations of the NixOS, user Nix, and Home
Manager profiles. Also show currently unreachable store paths and their
approximate total size.
Pass --apply to remove older generations, run the system GC, and optimise the
Nix store.

The script intentionally does not remove .direnv directories or result links:
inspect and remove those project-by-project when they are no longer needed.
EOF
}

apply=false
case "${1:-}" in
  "") ;;
  --apply) apply=true ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

expire_profile() {
  local profile="$1"
  local label="$2"
  local -a command=(nix-env --profile "$profile" --delete-generations "+$RETENTION_GENERATIONS")

  if [[ ! -L "$profile" ]]; then
    printf 'Skipping %s: %s does not exist.\n' "$label" "$profile"
    return
  fi

  printf '\n%s (%s)\n' "$label" "$profile"
  if [[ "$apply" == true ]]; then
    "${command[@]}"
  else
    "${command[@]}" --dry-run
  fi
}

expire_system_profile() {
  local -a command=(sudo nix-env --profile "$SYSTEM_PROFILE" --delete-generations "+$RETENTION_GENERATIONS")

  printf '\nNixOS system profile (%s)\n' "$SYSTEM_PROFILE"
  if [[ "$apply" == true ]]; then
    "${command[@]}"
  else
    "${command[@]}" --dry-run
  fi
}

expire_system_profile
expire_profile "$USER_PROFILE" "User Nix profile"
expire_profile "$HOME_MANAGER_PROFILE" "Home Manager profile"

if [[ "$apply" == true ]]; then
  printf '\nCollecting unreachable store paths...\n'
  sudo nix-collect-garbage

  printf '\nOptimising the Nix store (deduplicating identical files)...\n'
  sudo nix-store --optimise
else
  dead_paths_file=$(mktemp)
  trap 'rm -f "$dead_paths_file"' EXIT
  sudo nix-store --gc --print-dead --quiet > "$dead_paths_file"

  printf '\nCurrently unreachable store paths (first 20):\n'
  awk '
    NR <= 20 { print }
    END {
      if (NR == 0) print "(none)"
      printf "Total currently unreachable paths: %d\n", NR
      if (NR > 20) printf "... and %d more\n", NR - 20
    }
  ' "$dead_paths_file"
  size_bytes=0
  if [[ -s "$dead_paths_file" ]]; then
    size_bytes=$(xargs -r -d '\n' sudo nix path-info --size < "$dead_paths_file" | awk '{ bytes += $NF } END { printf "%.0f", bytes }')
  fi
  printf 'Approximate total NAR size: %s\n' "$(numfmt --to=iec-i --suffix=B "$size_bytes")"
  cat <<'EOF'

This was a preview; no generations or store paths were removed.
Removing generations may make additional store paths unreachable.
Re-run with --apply to perform this cleanup.
EOF
fi
