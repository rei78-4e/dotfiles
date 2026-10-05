# ╔═╗ ╔╗  ╔╗  ╦═╗
# ╠═╣ ╠╩╗ ╠╩╗ ╠╦╝
# ╩ ╩ ╚═╝ ╚═╝ ╩╚═

abbr -a copy wl-copy

abbr -a cdd 'cd $HOME/Develop'

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

abbr -a gst 'git status'
abbr -a gda 'git --no-pager diff'
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

abbr -a ls 'eza -l'
abbr -a lss 'ls -l'

# don't work on NixOS
abbr -a glist /run/current-system/sw/bin/ls

abbr -a img 'chafa -f kitty'

# shortcut launch commnads
abbr -a lg lazygit
abbr -a z ziggity
abbr -a rg 'rg --hidden'
abbr -a y yazi
abbr -a h 'hx .'
abbr -a mi mediainfo
abbr -a n 'nvim .'
abbr -a e 'emacs -nw .'
abbr -a oc opencode
abbr -a cl claude

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

#  ╔═╗ ╦═╗ ╔═╗ ╔═╗ ╦═╗ ╔═╗ ╔╦╗ ╔╦╗ ╦ ╔╗╔ ╔═╗
#  ╠═╝ ╠╦╝ ║ ║ ║ ╦ ╠╦╝ ╠═╣ ║║║ ║║║ ║ ║║║ ║ ╦
#  ╩   ╩╚═ ╚═╝ ╚═╝ ╩╚═ ╩ ╩ ╩ ╩ ╩ ╩ ╩ ╝╚╝ ╚═╝

# rust
abbr -a cb 'cargo build'
abbr -a cr 'cargo run'
abbr -a cf 'cargo fmt'
abbr -a ch 'cargo check'
abbr -a cn 'cp ~/dotfiles/rust_dev_temp/flake.nix ./flake.nix && ls ./flake.nix'

function blog
    cd ~/ghq/github.com/senox78/senox/
    nix develop -c $SHELL
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

abbr -a org 'cd $HOME/org && $EDITOR .'
