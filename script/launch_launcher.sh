#!/usr/bin/env bash

if systemctl --user is-active waybar.service; then
  rofi -show drun
else
  noctalia msg panel-toggle launcher;
fi
