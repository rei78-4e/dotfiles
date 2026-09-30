#!/usr/bin/env bash

lscpu -J | jq -r '
  (.lscpu | map({(.field): .data}) | add) as $cpu
  | ($cpu["Model name:"]
      | sub("^12th Gen "; "")
      | split("(R)") | join("")
      | split("(TM)") | join("")
    ) as $model
  | "\($model) (\($cpu["CPU(s):"]))"
'
