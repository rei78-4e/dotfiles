#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 rei78-4e
#
# battery-forecast.py
# ===================
#
# A drop-in replacement for Waybar's built-in `battery` module whose
# "Empty in ..." estimate takes your usual power draw at each time of day
# into account, instead of dividing the remaining energy by the
# instantaneous `power_now`.
#
# Features
# --------
# - Time-of-day profile: discharge samples from the last LOOKBACK_DAYS are
#   grouped into BIN_MIN-minute bins and the median watts of each bin is
#   used as the "usual" draw. Sparse bins borrow from neighbouring bins,
#   then fall back to the overall median.
# - Current draw: an EWMA (tau NOW_TAU) over the last NOW_WINDOW seconds of
#   samples plus the live `power_now` reading.
# - Forecast: steps forward STEP seconds at a time, blending from the
#   current draw to the profile with time constant BLEND_TAU, until the
#   remaining energy reaches zero (capped at HORIZON).
# - Charging: "Full in ..." from the live charge rate.
# - Stateless: nothing is stored or kept running. Each invocation reads
#   upower's history log (/var/lib/upower/history-rate-<model>-*-<serial>.dat)
#   and /sys/class/power_supply/BAT0, so it only needs upowerd to be
#   running. Python standard library only.
#
# Output
# ------
# One line of Waybar custom-module JSON:
#   text        icon + capacity, same formats as the built-in module
#   tooltip     estimate with ETA clock time, current vs usual watts,
#               naive estimate (energy_now / power_now), sample count
#   class       "warning" / "critical" by capacity (see STATES),
#               plus "charging" or "plugged"
#   percentage  capacity
#
# Usage
# -----
# Waybar config:
#   "modules-right": [ ..., "custom/battery", ... ],
#   "custom/battery": {
#     "exec": "~/dotfiles/script/battery-forecast.py",
#     "interval": 30,
#     "return-type": "json",
#     "format": "{}"
#   }
#
# Style it with `#custom-battery`, `#custom-battery.warning`,
# `#custom-battery.critical:not(.charging)` etc.
#
# Run it by hand to check the estimate:
#   ./battery-forecast.py | jq .
#
# Tune the constants below (lookback, bin size, blend speed, thresholds).
# A different battery can be used by changing BAT.
import glob
import json
import math
import os
import statistics
import time

BAT = "/sys/class/power_supply/BAT0"
HISTORY_DIR = "/var/lib/upower"

LOOKBACK_DAYS = 14
BIN_MIN = 30                # profile resolution
MIN_BIN_SAMPLES = 20        # ~10 min of upower samples (30s interval)
NOW_WINDOW = 10 * 60        # samples used for the current rate
NOW_TAU = 5 * 60            # EWMA time constant for the current rate
BLEND_TAU = 30 * 60         # how fast the forecast hands over to the profile
STEP = 60
HORIZON = 48 * 3600

STATES = {"warning": 30, "critical": 15}
ICONS = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]


def read(name, cast=str):
    try:
        with open(os.path.join(BAT, name)) as f:
            return cast(f.read().strip())
    except (OSError, ValueError):
        return None


def energy_wh(prefix):
    e = read(f"energy_{prefix}", int)
    if e is not None:
        return e / 1e6
    c, v = read(f"charge_{prefix}", int), read("voltage_now", int)
    return c * v / 1e12 if c is not None and v else None


def power_w():
    p = read("power_now", int)
    if p is not None:
        return p / 1e6
    i, v = read("current_now", int), read("voltage_now", int)
    return i * v / 1e12 if i is not None and v else None


def history_file():
    model, serial = read("model_name"), read("serial_number")
    if model and serial:
        hits = glob.glob(f"{HISTORY_DIR}/history-rate-{model}-*-{serial}.dat")
        if hits:
            return hits[0]
    return None


def discharge_samples(path, since):
    out = []
    try:
        with open(path) as f:
            for line in f:
                parts = line.split()
                if len(parts) != 3 or parts[2] != "discharging":
                    continue
                t, w = int(parts[0]), float(parts[1])
                if t >= since and w > 0:
                    out.append((t, w))
    except OSError:
        pass
    return out


def bin_of(ts):
    lt = time.localtime(ts)
    return (lt.tm_hour * 60 + lt.tm_min) // BIN_MIN


def build_profile(samples):
    nbins = 24 * 60 // BIN_MIN
    bins = [[] for _ in range(nbins)]
    for t, w in samples:
        bins[bin_of(t)].append(w)
    overall = statistics.median(w for _, w in samples) if samples else None

    profile = []
    for b in range(nbins):
        # widen to neighbouring bins until there is enough data
        for r in range(0, 4):
            pool = [w for d in range(-r, r + 1) for w in bins[(b + d) % nbins]]
            if len(pool) >= MIN_BIN_SAMPLES:
                profile.append(statistics.median(pool))
                break
        else:
            profile.append(overall)
    return profile, overall


def current_rate(samples, now, live):
    recent = [(t, w) for t, w in samples if t >= now - NOW_WINDOW]
    if live:
        recent.append((now, live))
    if not recent:
        return None
    num = den = 0.0
    for t, w in recent:
        k = math.exp(-(now - t) / NOW_TAU)
        num += k * w
        den += k
    return num / den


def forecast(energy, now, rate_now, profile):
    t, e = 0, energy
    while e > 0 and t < HORIZON:
        k = math.exp(-t / BLEND_TAU)
        usual = profile[bin_of(now + t)] if profile else None
        w = rate_now if usual is None else k * rate_now + (1 - k) * usual
        e -= w * STEP / 3600
        t += STEP
    # back off the overshoot of the last step
    return t + e / w * 3600 if e < 0 and w > 0 else t


def fmt_dur(sec):
    m = int(round(sec / 60))
    return f"{m // 60} h {m % 60:02d} min"


def main():
    now = int(time.time())
    status = read("status") or "Unknown"
    cap = read("capacity", int) or 0
    e_now, e_full, live = energy_wh("now"), energy_wh("full"), power_w()

    icon = ICONS[min(cap * len(ICONS) // 100, len(ICONS) - 1)]
    classes = [s for s, lim in STATES.items() if cap <= lim][-1:]
    lines = []

    if status == "Discharging" and e_now:
        path = history_file()
        samples = discharge_samples(path, now - LOOKBACK_DAYS * 86400) if path else []
        rate = current_rate(samples, now, live)
        profile, overall = build_profile(samples)
        if rate:
            sec = forecast(e_now, now, rate, profile)
            eta = time.strftime("%H:%M", time.localtime(now + sec))
            lines.append(f"Empty in {fmt_dur(sec)} (≈ {eta})")
            usual = profile[bin_of(now)] if profile else None
            detail = f"now {rate:.1f} W"
            if usual:
                detail += f" · usual {usual:.1f} W"
            lines.append(detail)
            if live:
                lines.append(f"naive {fmt_dur(e_now / live * 3600)}")
            lines.append(f"{len(samples)} samples / {LOOKBACK_DAYS} d")
        text = f"{icon}{cap}%"
    elif status == "Charging":
        classes.append("charging")
        text = f"󰂄 {cap}%"
        if e_now and e_full and live:
            lines.append(f"Full in {fmt_dur((e_full - e_now) / live * 3600)}")
    else:
        classes.append("plugged")
        text = f" {cap}%"
        lines.append(status)

    print(json.dumps({
        "text": text,
        "tooltip": "\n".join(lines) or status,
        "class": classes,
        "percentage": cap,
    }))


if __name__ == "__main__":
    main()
