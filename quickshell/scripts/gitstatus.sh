#!/usr/bin/env bash
# Git state of the project behind a window, for services/GitStatus.qml.
#
#   gitstatus.sh <pid>      prints  repo<TAB>branch<TAB>dirty<TAB>ahead<TAB>behind   (nothing = no repo)
#
# A terminal's own cwd is where it started; the shell (or editor) inside it is a child process, so
# the window's process tree is walked and the deepest process whose cwd is inside a repo wins.
pid=${1:-0}
[[ $pid -gt 0 ]] || exit 0

tree() {                       # pid and all its descendants, parents first (one ps, not a pgrep per process)
    ps -e -o pid=,ppid= | awk -v root="$1" '
        { kids[$2] = kids[$2] " " $1 }
        END { q[1] = root; n = 1
              for (i = 1; i <= n; i++) { print q[i]; m = split(kids[q[i]], a, " "); for (j = 1; j <= m; j++) q[++n] = a[j] } }'
}

dir=""
for p in $(tree "$pid" | tac); do
    d=$(readlink "/proc/$p/cwd" 2>/dev/null) || continue
    [[ $d == / || $d == "$HOME" ]] && continue
    if git -C "$d" rev-parse --show-toplevel >/dev/null 2>&1; then dir=$d; break; fi
done
[[ -n $dir ]] || exit 0

top=$(git -C "$dir" rev-parse --show-toplevel)
out=$(git -C "$dir" status --porcelain=v2 --branch 2>/dev/null) || exit 0
branch=$(sed -n 's/^# branch.head //p' <<<"$out")
[[ $branch == "(detached)" ]] && branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
ab=$(sed -n 's/^# branch.ab //p' <<<"$out")
ahead=0 behind=0
[[ -n $ab ]] && { ahead=${ab%% *}; ahead=${ahead#+}; behind=${ab##* }; behind=${behind#-}; }
dirty=$(grep -vc '^#' <<<"$out")
printf '%s\t%s\t%s\t%s\t%s\n' "$top" "$branch" "$dirty" "$ahead" "$behind"
