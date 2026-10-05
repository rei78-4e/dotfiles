status is-interactive; or return

function __done_sound --on-event fish_postexec
    test "$CMD_DURATION" -ge 10000; or return
    command -q pw-play; or return
    pw-play /run/current-system/sw/share/sounds/freedesktop/stereo/complete.oga &>/dev/null &
    disown
end
