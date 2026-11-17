#!/usr/bin/env fish
# figlet-styles: 全フォントの REI78 / Neve を1回の実行で表示
# 使い方: figlet-styles.fish             (リスト全フォント)
#         figlet-styles.fish doom slant  (指定フォントのみ)

set -l texts REI78 Neve
set -l colors '38;2;88;179;232' '38;2;60;159;230' # #58B3E8 / #3C9FE6 (SGR部)
set -l fonts slant shadow doom rounded standard big chunky bell
set -q argv[1]; and set fonts $argv

if not command -q figlet
    echo "figlet not found in PATH" >&2
    exit 1
end

for f in $fonts
    printf '\e[38;2;162;155;254m── %s ──\e[0m\n' $f
    set -l k 1
    for t in $texts
        printf '\e[%sm' $colors[$k]
        figlet -f $f $t | sed -e 's/[[:space:]]*$//' -e '/^$/d'
        printf '\e[0m'
        test $k -lt (count $texts); and echo
        set k (math "$k + 1")
    end
    echo
end
