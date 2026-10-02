#!/usr/bin/env bash

mode=${1:-memory}

awk -v mode="$mode" '
  /^MemTotal:/     { total = $2 }
  /^MemAvailable:/ { available = $2 }
  /^Cached:/       { cached = $2 }
  /^SReclaimable:/ { reclaimable = $2 }
  /^Shmem:/        { shared = $2 }
  END {
    used = total - available
    cache = cached + reclaimable - shared
    if (cache < 0) cache = 0
    if (mode == "cache") {
      printf "%.1f GiB\n", cache / 1048576
    } else {
      printf "%.1f / %.1f GiB (%.0f%%) · %.1f GiB available\n", used / 1048576, total / 1048576, used * 100 / total, available / 1048576
    }
  }
' /proc/meminfo
