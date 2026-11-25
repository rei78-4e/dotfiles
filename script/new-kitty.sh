#!/usr/bin/env bash


app=$(niri msg --json focused-window | jq -r '.app_id')
case "$app" in
    kitty) wtype -M ctrl -M shift n -m shift -m ctrl && echo "new by wtype";;
    *)     kitty --single-instance && echo "new kitty";;
esac
