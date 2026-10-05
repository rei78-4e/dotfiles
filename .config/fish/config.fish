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

    source $HOME/dotfiles/.config/fish/alias.fish
end

#  ╔╦╗ ╦ ╦ ╔═╗ ╔╦╗ ╔═╗
#   ║  ╠═╣ ║╣  ║║║ ║╣ 
#   ╩  ╩ ╩ ╚═╝ ╩ ╩ ╚═╝

fish_config theme choose "Rosé Pine Moon"

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
