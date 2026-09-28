#  ╔═╗ ╦ ╔═╗ ╦ ╦ ╔═╗ ╦═╗
#  ╠╣  ║ ╚═╗ ╠═╣ ║╣  ╠╦╝
#  ╚   ╩ ╚═╝ ╩ ╩ ╚═╝ ╩╚═

if test -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
else
    fish_add_path -g /nix/var/nix/profiles/default/bin
end
fish_add_path -g $HOME/.nix-profile/bin

if status is-interactive
    set -gx GPG_TTY (tty)

    if not type -q fisher
        curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
    end

    fish_config theme choose "Rosé Pine Moon"

    set -g fish_history_max 1000000
    set -g fish_greeting
    set -U fish_ambiguous_case_sensitive
    set -U fish_prompt_pwd_dir_length 0

    # direnv
    if type -q direnv
        direnv hook fish | source
    end
end

#  ╔╦╗ ╦ ╦ ╔═╗ ╔╦╗ ╔═╗
#   ║  ╠═╣ ║╣  ║║║ ║╣ 
#   ╩  ╩ ╩ ╚═╝ ╩ ╩ ╚═╝

fish_config theme choose "Rosé Pine Dawn"

# ╔═╗ ╔═╗ ╔╦╗ ╦ ╦
# ╠═╝ ╠═╣  ║  ╠═╣
# ╩   ╩ ╩  ╩  ╩ ╩

# cargo
fish_add_path -g $HOME/.cargo/bin
# My tools / apps
fish_add_path -g $HOME/my_apps/bin
# Moonbit
fish_add_path -g $HOME/.moon/bin
# brass
fish_add_path -g $HOME/.brass/bin
# go bin
if type -q go
    fish_add_path -g (go env GOPATH)/bin
end

# Linux
fish_add_path -g /opt/rocm/bin
fish_add_path -g $HOME/.local/bin/lap_tap
set -gx LD_LIBRARY_PATH $LD_LIBRARY_PATH /opt/rocm/lib
set -gx ROCM_PATH /opt/rocm
set -gx HSA_OVERRIDE_GFX_VERSION 10.3.0
set -gx OLLAMA_DEBUG 1
set -gx OLLAMA_HOST 0.0.0.0:11434
set -gx LIBVIRT_DEFAULT_URI qemu:///system
set -gx ZIGGITY_CONFIG "$HOME/.config/ziggity/config.ini"
# npm
fish_add_path -g $HOME/.npm-global/bin
fish_add_path -g $HOME/.cache/.bun/bin

if test -n "$SSH_CONNECTION"; and test -z "$TERM"
    set -gx TERM xterm-256color
end

if test -z "$SSH_AUTH_SOCK"; and test -S "$XDG_RUNTIME_DIR/gcr/ssh"
    set -gx SSH_AUTH_SOCK "$XDG_RUNTIME_DIR/gcr/ssh"
end

# ╔═╗ ╔╗╔ ╦  ╦
# ║╣  ║║║ ╚╗╔╝
# ╚═╝ ╝╚╝  ╚╝

set -gx GTK_IM_MODULE fcitx
set -gx QT_IM_MODULE fcitx
set -gx XMODIFIERS @im=fcitx
set -gx HYPRSHOT_DIR "$HOME/Desktop/"

set -gx EDITOR hx
set -gx NPM_CONFIG_PREFIX $HOME/.npm-global
set -gx BUN_INSTALL $HOME/.cache/.bun

if test -f "$HOME/.env"
    for line in (grep -v '^#' "$HOME/.env")
        set -l item (string split -m 1 '=' $line)
        test -n "$item[1]"; and set -gx $item[1] $item[2]
    end
end

# ╔═╗ ╔╗  ╔╗  ╦═╗
# ╠═╣ ╠╩╗ ╠╩╗ ╠╦╝
# ╩ ╩ ╚═╝ ╚═╝ ╩╚═

abbr -a mkmk toup
abbr -a copy wl-copy
abbr -a c wl-copy

# ╔═╗ ╔╦╗   ╔═╗ ╔╗  ╔╗  ╦═╗
# ║    ║║   ╠═╣ ╠╩╗ ╠╩╗ ╠╦╝
# ╚═╝ ═╩╝   ╩ ╩ ╚═╝ ╚═╝ ╩╚═

abbr -a cdd 'cd $HOME/Develop'
abbr -a cdo 'cd $HOME/org'

function g
    set -l repo (ghq list | fzf --preview 'ls (ghq root)/{}')
    and test -n "$repo"
    and cd (ghq root)/$repo
end

function gg
    set -l dir (fd . "$HOME/Develop" --max-depth 1 --type d |
        sed "s|$HOME/Develop/||" |
        fzf --preview 'eza "$HOME/Develop/{}"')

    test -n "$dir"; and cd "$HOME/Develop/$dir"
end

function yy
    set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    set -l cwd (cat -- "$tmp")
    if test -n "$cwd"; and test "$cwd" != "$PWD"
        cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

# ╔═╗ ╦ ╔╦╗      ╔═╗ ╔╗  ╔╗  ╦═╗
# ║ ╦ ║  ║       ╠═╣ ╠╩╗ ╠╩╗ ╠╦╝
# ╚═╝ ╩  ╩       ╩ ╩ ╚═╝ ╚═╝ ╩╚═
abbr -a gst 'git status'
abbr -a gda 'git --no-pager diff'
function git-log
    set -l limit

    if test (count $argv) -gt 0
        set limit -n "$argv[1]"
    end

    git --no-pager log --all --date-order \
        --date=format:'%y-%m-%d %H:%M' \
        --graph \
        --format=' <%h> %ad [%an] [%G?] %C(green)%d%Creset %s' \
        $limit |
        awk '{
        gsub(/\[G\]/, "✓")
        gsub(/\[U\]/, "△")
        gsub(/\[B\]/, "✗")
        gsub(/\[E\]/, "!")
        gsub(/\[N\]/, "·")
        print
    }'
end

abbr -a gla git-log
abbr -a gls "git-log 15"
abbr -a gf 'git fetch'
abbr -a gb 'git branch'

function gc
    git add .
    git commit -m "$argv[1]"
end

#  ╦ ╦ ╔╦╗ ╦ ╦   ╔═╗      ╔═╗ ╔╗  ╔╗  ╦═╗
#  ║ ║  ║  ║ ║   ╚═╗      ╠═╣ ╠╩╗ ╠╩╗ ╠╦╝
#  ╚═╝  ╩  ╩ ╩═╝ ╚═╝      ╩ ╩ ╚═╝ ╚═╝ ╩╚═

abbr -a l 'eza --icons=always -l'
abbr -a lss 'ls -l'
abbr -a ls 'eza -l'

# don't work on NixOS
abbr -a glist /bin/ls

abbr -a img 'chafa -f kitty'

abbr -a rtss 'rts -cli | jq -r ".list[] | \"title: \\(.title)\\nlink: \\(.link)\\n\""'

# shortcut launch commnads
abbr -a lg lazygit
abbr -a z ziggity
abbr -a rg 'rg --hidden'
abbr -a y yazi
abbr -a h 'hxd .'
abbr -a mi mediainfo
abbr -a n 'nvim .'
abbr -a e 'emacs -nw .'
abbr -a oc opencode

abbr -a reboot 'systemctl reboot'

function toup
    mkdir -p (dirname "$argv[1]") && touch "$argv[1]"
end

# tmux
abbr -a tl 'tmux ls'
abbr -a tmr 'tmux kill-session -t'

function ta --description 'Attach or create a tmux session'
    if test -n "$argv[1]"
        tmux new-session -A -s $argv[1]
    else
        tmux
    end
end

function wifi
    nmcli device wifi rescan 2>/dev/null
    sleep 1
    set -l saved (nmcli -g NAME connection show)

    set -l ssid (nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list |
        awk -F: -v saved="$(string join \n $saved)" '
          BEGIN { n=split(saved, a, "\n"); for(i=1;i<=n;i++) s[a[i]]=1 }
          NF>=4 && $4!="" && !seen[$4]++ {
            cur  = ($1 == "*") ? "▶" : " "
            mark = ($4 in s)   ? "*" : " "
            printf "%s%s %3s%%  %-10s %s\n", cur, mark, $2, $3, $4
          }' |
        sort -k2 -rn |
        fzf --layout=reverse --border --prompt="Wi-Fi > " --header="▶ = connected, * = saved" |
        sed 's/^.\{2\} *[0-9]*% *[^ ]* *//')

    test -n "$ssid"; and nmcli device wifi connect "$ssid" --ask
end

#  ╔═╗ ╦═╗ ╔═╗ ╔═╗ ╦═╗ ╔═╗ ╔╦╗ ╔╦╗ ╦ ╔╗╔ ╔═╗
#  ╠═╝ ╠╦╝ ║ ║ ║ ╦ ╠╦╝ ╠═╣ ║║║ ║║║ ║ ║║║ ║ ╦
#  ╩   ╩╚═ ╚═╝ ╚═╝ ╩╚═ ╩ ╩ ╩ ╩ ╩ ╩ ╩ ╝╚╝ ╚═╝

# rust
abbr -a cb 'cargo build'
abbr -a cr 'cargo run'
abbr -a cf 'cargo fmt'
abbr -a ch 'cargo check'
abbr -a cn 'cp ~/dotfiles/rust_dev_temp/flake.nix ./flake.nix && ls ./flake.nix'

# moonbit
abbr -a mb 'moon build'
abbr -a mr 'moon run'
abbr -a mf 'moon fmt'
abbr -a mh 'moon check'

#gleam
abbr -a gb 'gleam build'
abbr -a gr 'gleam run'

function blog
    cd ~/ghq/github.com/senox78/senox/
    nix develop -c $SHELL
    # ./new
end

# ╔╗╔ ╦ ═╗ ╦
# ║║║ ║ ╔╩╦╝
# ╝╚╝ ╩ ╩ ╚═

abbr -a nd 'nix develop -c $SHELL'
abbr -a update 'nix flake update'
abbr -a ns 'nix search nixpkgs'

function rebuild_host
    if test -f /etc/dotfiles-host
        set -l host (string trim (cat /etc/dotfiles-host))
        if test -f "$HOME/dotfiles/hosts/$host/configuration.nix"
            echo $host
            return 0
        end
        echo "rebuild: invalid host in /etc/dotfiles-host: $host" >&2
        return 1
    end

    set -l cur (hostname)
    for dir in $HOME/dotfiles/hosts/*/
        if grep -q "networking.hostName = \"$cur\"" $dir/configuration.nix 2>/dev/null
            path basename $dir
            return 0
        end
    end

    # Old hostname during the transition to neve, before /etc/dotfiles-host exists.
    if test "$cur" = selinoir
        echo thinkpad
        return 0
    end

    echo "rebuild: no host configuration found for hostname $cur" >&2
    return 1
end

function rebuild
    set -l opts
    if contains -- --local $argv
        set opts --option builders ''
        echo "rebuild: remote builder disabled (--local); builders=\"\""
    end

    if test (uname -s) = Darwin
        echo "sudo darwin-rebuild switch --flake $HOME/dotfiles#macbook $opts"
        sudo darwin-rebuild switch --flake $HOME/dotfiles#macbook $opts
    else if test -f /etc/NIXOS
        set -l host (rebuild_host)
        or return 1
        echo "sudo nixos-rebuild switch --flake .#$host $opts"
        sudo nixos-rebuild switch --flake .#$host $opts
    else
        set -l flake_user (nix eval --raw .#lib.userName); or return
        echo "home-manager switch --flake .#$flake_user"
        home-manager switch --flake ".#$flake_user"
    end
end

abbr -a org 'cd $HOME/org && nvim .'
