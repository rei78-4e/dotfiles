# ╔═╗ ╔╗  ╔╗  ╦═╗
# ╠═╣ ╠╩╗ ╠╩╗ ╠╦╝
# ╩ ╩ ╚═╝ ╚═╝ ╩╚═

abbr -a copy wl-copy
abbr -a fastfetch 'fastfetch --logo "$(shuf -n 1 -e ~/Pictures/ff_logos/*.png)"'
abbr -a cdd 'cd $HOME/Develop'

#  ╔╦╗ ╔═╗ ╔╦╗ ╦ ╦
#  ║║║ ╠═╣  ║  ╠═╣
#  ╩ ╩ ╩ ╩  ╩  ╩ ╩

function +
    set res $argv[1]
    for i in $argv[2..-1]
        set res (math $i + $res)
    end
    echo $res
end

function s
    set res $argv[1]
    for i in $argv[2..-1]
        set res (math $res - $i)
    end
    echo $res
end

function x
    set res $argv[1]
    for i in $argv[2..-1]
        set res (math $res * $i)
    end
    echo $res
end

function d
    set res $argv[1]
    for i in $argv[2..-1]
        set res (math $res / $i)
    end
    echo $res
end

function or_default
    if test -n "$argv[1]"
        printf '%s\n' $argv[1]
    else
        printf '%s\n' $argv[2]
    end
end

function g
    set -l repo (ghq list | fzf --preview 'ls (ghq root)/{}')
    and test -n "$repo"
    and cd (ghq root)/$repo
end

function gg
    set -l dir (eza -1 -s modified -r --only-dirs "$HOME/Develop" |
        fzf --no-sort --preview 'eza "$HOME/Develop/{}"')

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
abbr -a v 'vim .'
abbr -a e 'emacs -nw .'
abbr -a oc opencode
abbr -a ai 'cd $HOME/org && opencode'
abbr -a cl claude

function toup
    mkdir -p (dirname "$argv[1]") && touch "$argv[1]"
end

# tmux
abbr -a tmr 'tmux kill-session -t'

#  ╔╦╗ ╔╦╗ ╦ ╦  ╦ ╦      ╔═╗ ╦ ╦ ╔╗╔ ╔═╗
#   ║  ║║║ ║ ║ ╔╩╦╝      ╠╣  ║ ║ ║║║ ║  
#   ╩  ╩ ╩ ╚═╝ ╩ ╩       ╚   ╚═╝ ╝╚╝ ╚═╝

function tl --description 'Pick or create a tmux session with fzf'
    set -l sessions (tmux list-sessions -F '#{session_name}' 2>/dev/null)

    set -l picked (
        begin
            if set -q sessions[1]
                printf '%s\n' $sessions
            end
        end | fzf --prompt='tmux session> ' \
                  --header='Enter: open   (type a new name to create)' \
                  --print-query |
            tail -n 1
    )

    test -n "$picked"; or return 0

    if not set -q TMUX
        ta $picked
        return
    end

    if not tmux has-session -t "=$picked" 2>/dev/null
        tmux new-session -d -s $picked
    end
    tmux switch-client -t "=$picked"
end

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

abbr -a Ruby 'cd $HOME/Develop/lang/Ruby &&
              clear &&
              nix develop -c irb --simple-prompt'

abbr -a lang 'cd $HOME/Develop/lang'

#  ╔═╗ ╦═╗ ╔═╗    ╔╦╗ ╔═╗ ╔╦╗ ╔═╗      ╔═╗ ╦ ╦ ╔╗╔
#  ║ ║ ╠╦╝ ║ ╦ ── ║║║ ║ ║  ║║ ║╣       ╠╣  ║ ║ ║║║
#  ╚═╝ ╩╚═ ╚═╝    ╩ ╩ ╚═╝ ═╩╝ ╚═╝      ╚   ╚═╝ ╝╚╝

function jl --description "today journal.org"
    set -q argv[1]; or set argv[1] "$HOME/org/journal.org"
    set target $argv[1]
    echo $target

    mkdir -p (dirname "$target")
    test -e "$target"; or touch "$target"

    set dt_lst \
        "* "(date "+%Y") \
        "** "(date "+%Y-%m %B") \
        "*** "(date "+%Y-%m-%d %a")

    for dt in $dt_lst
        if not grep -qxF "$dt" "$target" 2>/dev/null
            echo "$dt" >>"$target"
        end
    end

    test -n (tail -n 1 "$target"); and echo "" >>"$target"
    $EDITOR "$target:"(count (cat "$target"))
end

function tt --description "add to inbox.org"
    set -l file ~/org/inbox.org
    set -l title $argv[1]
    set -l in_dt $argv[2]
    set -l pos (grep -n -i -E '#\+(title|author|date|startup|todo|keywords|subtitle|description|language)' $file | tail -n 1 | cut -d: -f1)

    set -l tm
    test -z "$title"; and read -P "title: " title
    if test -z "$in_dt"
        read -P "date(skip=s): " in_dt
        if test "$in_dt" = s; or test "$in_dt" = S
            set in_dt
        else
            set dt (date -d "$in_dt" "+<%Y-%m-%d %a>")
            and printf "⇒ %s\n" $dt >&2
        end
    end

    set -l tmp (mktemp)

    set -l lines (printf "\n* TODO %s" $title)
    test -n "$in_dt"; and set -a lines $dt
    printf '%s\n' $lines >$tmp
    sed -i "$pos r $tmp" $file
    rm $tmp

    read -n 1 -P "open(y/n)?" ans
    if string match -qi y -- $ans
        $EDITOR "$file:"(+ $pos 3)
    end
end
